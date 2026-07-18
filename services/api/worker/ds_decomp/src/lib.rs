use pyo3::prelude::*;
use pyo3::types::{PyAny, PyBytes, PyByteArray, PyDict, PyList, PyTuple};

#[derive(Clone, Debug)]
struct ColMeta {
    dtype: String,
    min: i64,
    bits: u32,
    packed_bits: u32,
    pixels: Option<usize>,
    rows: usize,
}

#[derive(Clone, Debug)]
enum ColValue {
    Int(i64),
    Float(f32),
    Text(String),
    Image(Vec<u8>),
}

fn err<T>(msg: impl Into<String>) -> PyResult<T> {
    Err(pyo3::exceptions::PyValueError::new_err(msg.into()))
}

/* ---------------- RLE ---------------- */

fn rle_decode(data: &[u8]) -> PyResult<Vec<u8>> {
    let mut out = Vec::new();
    let mut i = 0usize;

    while i < data.len() {
        if i + 2 >= data.len() {
            return err("RLE corrupted: truncated run header");
        }
        let run_len = ((data[i] as usize) << 8) | (data[i + 1] as usize);
        let value = data[i + 2];
        i += 3;

        out.reserve(run_len);
        out.extend(std::iter::repeat(value).take(run_len));
    }
    Ok(out)
}

fn rle_decode_adaptive(data: &[u8]) -> PyResult<Vec<u8>> {
    if data.is_empty() {
        return Ok(Vec::new());
    }
    match data[0] {
        0 => Ok(data[1..].to_vec()),
        1 => rle_decode(&data[1..]),
        f => err(format!("Invalid RLE flag byte: {f}")),
    }
}

/* ---------------- BIT PACK ---------------- */

fn bit_unpack(data: &[u8], bits: u32, count: usize) -> PyResult<Vec<u32>> {
    if bits == 0 || bits > 32 {
        return err("bit_unpack: bits must be in 1..=32");
    }

    let total_bits = data.len() * 8;
    let mut bit_pos = 0usize;
    let mut out = Vec::with_capacity(count);

    for _ in 0..count {
        if bit_pos + bits as usize > total_bits {
            return err("bit-packed integer column truncated");
        }

        let mut value = 0u32;
        for b in 0..bits {
            let abs = bit_pos + b as usize;
            let byte_i = abs >> 3;
            let bit_i = 7 - (abs & 7);
            let bit = (data[byte_i] >> bit_i) & 1;
            value = (value << 1) | bit as u32;
        }

        out.push(value);
        bit_pos += bits as usize;
    }

    Ok(out)
}

/* ---------------- COLUMN DECODING ---------------- */

fn decode_numeric(payload: &[u8], meta: &ColMeta, blocks_mode: bool) -> PyResult<Vec<ColValue>> {
    let mn = meta.min;
    let bits = meta.bits;

    if matches!(bits, 8 | 16 | 32) {
        let step = (bits / 8) as usize;
        if payload.len() % step != 0 {
            return err("numeric column payload size mismatch");
        }

        let mut out = Vec::with_capacity(payload.len() / step);
        match step {
            1 => payload.iter().for_each(|&b| out.push(ColValue::Int(mn + b as i64))),
            2 => {
                for i in (0..payload.len()).step_by(2) {
                    let v = ((payload[i] as i64) << 8) | payload[i + 1] as i64;
                    out.push(ColValue::Int(mn + v));
                }
            }
            4 => {
                for i in (0..payload.len()).step_by(4) {
                    let v = ((payload[i] as i64) << 24)
                        | ((payload[i + 1] as i64) << 16)
                        | ((payload[i + 2] as i64) << 8)
                        | payload[i + 3] as i64;
                    out.push(ColValue::Int(mn + v));
                }
            }
            _ => unreachable!(),
        }
        return Ok(out);
    }

    let packed = if meta.packed_bits != 0 { meta.packed_bits } else { meta.bits };
    if packed > 0 {
        if blocks_mode {
            return err("bit-packed numeric decoding unsupported in block mode");
        }
        return Ok(bit_unpack(payload, packed, meta.rows)?
            .into_iter()
            .map(|v| ColValue::Int(mn + v as i64))
            .collect());
    }

    err("cannot infer numeric decoding parameters")
}

fn decode_column_one_stream(encoded: &[u8], meta: &ColMeta, blocks: bool) -> PyResult<Vec<ColValue>> {
    let payload = rle_decode_adaptive(encoded)?;
    match meta.dtype.as_str() {
        "num" => decode_numeric(&payload, meta, blocks),
        "float" => Ok(payload.iter().map(|&b| ColValue::Float(b as f32 / 255.0)).collect()),
        "image" => {
            let p = meta.pixels.ok_or_else(|| {
                pyo3::exceptions::PyValueError::new_err("image requires pixels")
            })?;
            if payload.len() % p != 0 {
                return err("image column size mismatch");
            }
            Ok(payload.chunks(p).map(|c| ColValue::Image(c.to_vec())).collect())
        }
        "text" => {
            let mut out: Vec<_> = payload
                .split(|&b| b == 0)
                .map(|c| ColValue::Text(String::from_utf8_lossy(c).into_owned()))
                .collect();

            if out.len() < meta.rows {
                out.resize(meta.rows, ColValue::Text(String::new()));
            }
            if out.len() > meta.rows {
                out.truncate(meta.rows);
            }
            Ok(out)
        }
        other => err(format!("Unknown dtype: {other}")),
    }
}

/* ---------------- PY HELPERS ---------------- */

fn extract_bytes(obj: &Bound<'_, PyAny>) -> Option<Vec<u8>> {
    if let Ok(b) = obj.downcast::<PyBytes>() {
        Some(b.as_bytes().to_vec())
    } else if let Ok(b) = obj.downcast::<PyByteArray>() {
        Some(b.to_vec())
    } else {
        None
    }
}

fn decode_column_any(_py: Python<'_>, obj: &Bound<'_, PyAny>, meta: &ColMeta) -> PyResult<Vec<ColValue>> {
    if let Some(buf) = extract_bytes(obj) {
        return decode_column_one_stream(&buf, meta, false);
    }

    if let Ok(list) = obj.downcast::<PyList>() {
        let mut out = Vec::new();
        for item in list.iter() {
            let Some(buf) = extract_bytes(&item) else {
                return err("column block must be bytes");
            };
            if !buf.is_empty() {
                out.extend(decode_column_one_stream(&buf, meta, true)?);
            }
        }
        return Ok(out);
    }

    err(format!("Unexpected column format: {}", obj.get_type().name()?))
}

fn col_value_to_py(py: Python<'_>, v: &ColValue) -> PyObject {
    match v {
        ColValue::Int(x) => x.into_py(py),
        ColValue::Float(x) => x.into_py(py),
        ColValue::Text(s) => s.into_py(py),
        ColValue::Image(bytes) => {
            let lst = PyList::empty(py);
            for b in bytes {
                lst.append(*b as u32).unwrap();
            }
            lst.into_py(py)
        }
    }
}

/* ---------------- MAIN ENTRY ---------------- */
#[pyfunction]
fn decompress_dataset(py: Python<'_>, packet: &Bound<'_, PyAny>) -> PyResult<PyObject> {
    let packet = packet.downcast::<PyDict>()?;

    let header_any = packet.get_item("header")?.unwrap();
    let header = header_any.downcast::<PyDict>()?;

    let data_any = packet.get_item("data")?.unwrap();
    let data = data_any.downcast::<PyList>()?;

    let rows: usize = header.get_item("rows")?.unwrap().extract()?;
    let ic: usize = header.get_item("inputs_count")?.unwrap().extract()?;
    let oc: usize = header.get_item("outputs_count")?.unwrap().extract()?;

    let columns_any = header.get_item("columns")?.unwrap();
    let columns = columns_any.downcast::<PyDict>()?;

    let mut meta = std::collections::HashMap::new();
    for (k, v) in columns.iter() {
        let key = k.extract::<String>()?;
        let d = v.downcast::<PyDict>()?;
        meta.insert(
            key,
            ColMeta {
                dtype: d.get_item("dtype")?.unwrap().extract()?,
                min: d.get_item("min")?.map(|v| v.extract().unwrap()).unwrap_or(0),
                bits: d.get_item("bits")?.map(|v| v.extract().unwrap()).unwrap_or(0),
                packed_bits: d.get_item("packed_bits")?.map(|v| v.extract().unwrap()).unwrap_or(0),
                pixels: d.get_item("pixels")?.map(|v| v.extract().unwrap()),
                rows,
            },
        );
    }

    let ins_any = data.get_item(0)?;
    let ins = ins_any.downcast::<PyList>()?;

    let outs_any = data.get_item(1)?;
    let outs = outs_any.downcast::<PyList>()?;

    let mut din = Vec::new();
    let mut dout = Vec::new();

    for i in 0..ic {
        let col_any = ins.get_item(i)?;
        din.push(decode_column_any(py, &col_any, &meta[&i.to_string()])?);
    }

    for i in 0..oc {
        let col_any = outs.get_item(i)?;
        dout.push(decode_column_any(
            py,
            &col_any,
            &meta[&(i + ic).to_string()],
        )?);
    }

    let ds = PyList::empty(py);
    for r in 0..rows {
        let a = PyList::empty(py);
        let b = PyList::empty(py);

        for i in 0..ic {
            a.append(col_value_to_py(py, &din[i][r]))?;
        }
        for j in 0..oc {
            b.append(col_value_to_py(py, &dout[j][r]))?;
        }

        let tup = PyTuple::new(py, &[a.into_any(), b.into_any()])?;
        ds.append(tup)?;
    }

    Ok(ds.into_py(py))
}


#[pymodule]
fn ds_decompressor(_py: Python<'_>, m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(decompress_dataset, m)?)?;
    Ok(())
}
