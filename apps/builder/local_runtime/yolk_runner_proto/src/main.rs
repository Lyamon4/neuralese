use std::env;
use std::fs::File;
use std::io::{self, BufRead, Read, Seek, SeekFrom};

use anyhow::{anyhow, bail, Context, Result};
use ndarray::IxDyn;
use ort::session::builder::{GraphOptimizationLevel, SessionBuilder};
use ort::session::{Session, SessionOutputs};
use serde_json::Value as JsonValue;

const MAGIC: &[u8; 16] = b"NLESE_YOLK_v001!";

fn main() -> Result<()> {
    println!(
r#" __    __  ________  __    __  _______    ______   __        ________   ______   ________
/  \  /  |/        |/  |  /  |/       \  /      \ /  |      /        | /      \ /        |
$$  \ $$ |$$$$$$$$/ $$ |  $$ |$$$$$$$  |/$$$$$$  |$$ |      $$$$$$$$/ /$$$$$$  |$$$$$$$$/
$$$  \$$ |$$ |__    $$ |  $$ |$$ |__$$ |$$ |__$$ |$$ |      $$ |__    $$ \__$$/ $$ |__
$$$$  $$ |$$    |   $$ |  $$ |$$    $$< $$    $$ |$$ |      $$    |   $$      \ $$    |
$$ $$ $$ |$$$$$/    $$ |  $$ |$$$$$$$  |$$$$$$$$ |$$ |      $$$$$/     $$$$$$  |$$$$$/
$$ |$$$$ |$$ |_____ $$ \__$$ |$$ |  $$ |$$ |  $$ |$$ |_____ $$ |_____ /  \__$$ |$$ |_____
$$ | $$$ |$$       |$$    $$/ $$ |  $$ |$$ |  $$ |$$       |$$       |$$    $$/ $$       |
$$/   $$/ $$$$$$$$/  $$$$$$/  $$/   $$/ $$/   $$/ $$$$$$$$/ $$$$$$$$/  $$$$$$/  $$$$$$$$/
"#
    );
    println!("──────────────────────────────────────────────────────────────");
    println!("Neuralese Yolk Runtime");
    println!("──────────────────────────────────────────────────────────────\n");

    println!("Initializing runtime environment...");
    let (meta_str, model_bytes) = extract_payload().context("failed to read bundled ONNX payload")?;
    let meta = parse_meta(&meta_str)?;

    let mut session = SessionBuilder::new()
        .map_err(|err| anyhow!("{err}"))?
        .with_optimization_level(GraphOptimizationLevel::Level3)
        .map_err(|err| anyhow!("{err}"))?
        .commit_from_memory(&model_bytes)
        .map_err(|err| anyhow!("{err}"))?;

    println!("Model successfully loaded.");
    println!(" Input shape : {:?}", meta.input_shape);
    println!(" Input dtype : {}\n", meta.input_dtype);

    println!("Enter input tensors as JSON-like arrays, e.g. [1, 0, 0, 1, 0]");
    println!("Press Ctrl+C to terminate.\n");

    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let raw = line?;
        let raw = raw.trim();
        if raw.is_empty() {
            continue;
        }
        match process_input(raw, &meta, &mut session) {
            Ok(()) => {}
            Err(err) => eprintln!("{err:#}"),
        }
    }
    Ok(())
}

#[derive(Debug)]
struct ModelMeta {
    input_shape: Vec<usize>,
    input_dtype: String,
}

fn parse_meta(meta_str: &str) -> Result<ModelMeta> {
    let meta: JsonValue = serde_json::from_str(meta_str)?;
    let shape = meta
        .get("input_shape")
        .and_then(|v| v.as_array())
        .context("metadata missing input_shape array")?
        .iter()
        .map(|v| v.as_u64().map(|n| n as usize).context("input_shape must contain integers"))
        .collect::<Result<Vec<_>>>()?;
    let dtype = meta
        .get("input_dtype")
        .and_then(|v| v.as_str())
        .unwrap_or("f32")
        .to_string();
    Ok(ModelMeta {
        input_shape: shape,
        input_dtype: dtype,
    })
}

fn extract_payload() -> io::Result<(String, Vec<u8>)> {
    let exe_path = env::current_exe()?;
    let mut file = File::open(exe_path)?;
    let file_len = file.metadata()?.len();
    if file_len < 32 {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "executable too small"));
    }

    let mut magic = [0u8; 16];
    file.seek(SeekFrom::End(-16))?;
    file.read_exact(&mut magic)?;
    if magic != *MAGIC {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "payload magic mismatch"));
    }

    let mut lens = [0u8; 16];
    file.seek(SeekFrom::End(-32))?;
    file.read_exact(&mut lens)?;
    let meta_len = u64::from_le_bytes(lens[0..8].try_into().unwrap());
    let model_len = u64::from_le_bytes(lens[8..16].try_into().unwrap());
    let payload_len = model_len
        .checked_add(meta_len)
        .and_then(|n| n.checked_add(32))
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "payload length overflow"))?;
    if payload_len > file_len {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "payload exceeds file size"));
    }

    let model_start = file_len - payload_len;
    let meta_start = model_start + model_len;

    file.seek(SeekFrom::Start(model_start))?;
    let mut model_bytes = vec![0u8; model_len as usize];
    file.read_exact(&mut model_bytes)?;

    file.seek(SeekFrom::Start(meta_start))?;
    let mut meta_bytes = vec![0u8; meta_len as usize];
    file.read_exact(&mut meta_bytes)?;

    let meta_str = String::from_utf8(meta_bytes)
        .map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))?;
    Ok((meta_str, model_bytes))
}

fn parse_array(raw: &str, shape: &[usize]) -> Result<Vec<f32>> {
    let parsed: JsonValue = serde_json::from_str(raw)?;
    let mut values = Vec::new();
    flatten_numbers(&parsed, &mut values)?;
    let expected: usize = shape.iter().product();
    if values.len() != expected {
        bail!("input length {} != expected {}", values.len(), expected);
    }
    Ok(values)
}

fn flatten_numbers(value: &JsonValue, out: &mut Vec<f32>) -> Result<()> {
    match value {
        JsonValue::Array(items) => {
            for item in items {
                flatten_numbers(item, out)?;
            }
        }
        JsonValue::Number(n) => {
            let v = n.as_f64().context("number is not representable")?;
            out.push(v as f32);
        }
        _ => bail!("input must be a JSON array of numbers"),
    }
    Ok(())
}

fn process_input(raw: &str, meta: &ModelMeta, session: &mut Session) -> Result<()> {
    let vec_f32 = parse_array(raw, &meta.input_shape)?;
    match meta.input_dtype.as_str() {
        "i8" | "int8" => {
            let data: Vec<i8> = vec_f32.iter().map(|x| x.round() as i8).collect();
            let arr = ndarray::ArrayD::from_shape_vec(IxDyn(&meta.input_shape), data)?;
            let tensor = ort::value::Tensor::from_array(arr).map_err(|err| anyhow!("{err}"))?;
            let out = session.run(ort::inputs![tensor]).map_err(|err| anyhow!("{err}"))?;
            dump_outputs(&out)?;
        }
        "u8" | "uint8" => {
            let data: Vec<u8> = vec_f32.iter().map(|x| x.round().clamp(0.0, 255.0) as u8).collect();
            let arr = ndarray::ArrayD::from_shape_vec(IxDyn(&meta.input_shape), data)?;
            let tensor = ort::value::Tensor::from_array(arr).map_err(|err| anyhow!("{err}"))?;
            let out = session.run(ort::inputs![tensor]).map_err(|err| anyhow!("{err}"))?;
            dump_outputs(&out)?;
        }
        _ => {
            let arr = ndarray::ArrayD::<f32>::from_shape_vec(IxDyn(&meta.input_shape), vec_f32)?;
            let tensor = ort::value::Tensor::from_array(arr).map_err(|err| anyhow!("{err}"))?;
            let out = session.run(ort::inputs![tensor]).map_err(|err| anyhow!("{err}"))?;
            dump_outputs(&out)?;
        }
    }
    Ok(())
}

fn dump_outputs(outputs: &SessionOutputs) -> Result<()> {
    let mut printed = false;
    for (_name, value) in outputs.iter() {
        if let Ok(v) = value.try_extract_array::<f32>() {
            println!("{:?}", v.as_slice().context("output array is not contiguous")?);
            printed = true;
        } else if let Ok(v) = value.try_extract_array::<i8>() {
            println!("{:?}", v.as_slice().context("output array is not contiguous")?);
            printed = true;
        } else if let Ok(v) = value.try_extract_array::<u8>() {
            println!("{:?}", v.as_slice().context("output array is not contiguous")?);
            printed = true;
        } else if let Ok(v) = value.try_extract_array::<i32>() {
            println!("{:?}", v.as_slice().context("output array is not contiguous")?);
            printed = true;
        } else if let Ok(v) = value.try_extract_array::<f64>() {
            println!("{:?}", v.as_slice().context("output array is not contiguous")?);
            printed = true;
        }
    }
    if !printed {
        bail!("model produced no printable outputs");
    }
    Ok(())
}
