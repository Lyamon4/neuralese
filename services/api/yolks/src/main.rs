
use std::env;
use std::fs::File;
use std::io::{self, BufRead, Read, Seek, SeekFrom};
use anyhow::Result;
use ndarray::{ArrayD, IxDyn};
use ort::{
	session::builder::{GraphOptimizationLevel, SessionBuilder},
	session::Session,
	value::Tensor,
};
use serde_json::Value as JsonValue;

// Footer magic
const MAGIC: &[u8; 16] = b"YOLK_FOOTER_v1__";

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
	let (meta_str, model_bytes) = extract_footer()?;
	let (input_shape, input_dtype) = parse_meta(&meta_str)
	?;

	let mut session = SessionBuilder::new()?
		.with_optimization_level(GraphOptimizationLevel::Level3)?
		.commit_from_memory(&model_bytes)?;

	println!("Model successfully loaded.");
	println!(" Input shape : {:?}", input_shape);
	println!(" Input dtype : {}\n", input_dtype);

	println!("Enter input tensors as JSON-like arrays, e.g. [1, 0, 0, 1, 0]");
	println!("Press Ctrl+C to terminate.\n");

	let stdin = io::stdin();
	for line in stdin.lock().lines() {
		let raw = line?;
		if raw.trim().is_empty() {
			continue;
		}
		if let Err(e) = process_input(&raw, &input_shape, &input_dtype, &mut session) {
			eprintln!("Error: {e:?}");
		}
	}
	Ok(())
}


// -----------------------------------------------------------------------------
// Footer reader
// -----------------------------------------------------------------------------
fn extract_footer() -> std::io::Result<(String, Vec<u8>)> {
	let exe_path = env::current_exe()?;
	let mut f = File::open(&exe_path)?;
	let file_len = f.metadata()?.len();

	let mut buf = [0u8; 16];
	f.seek(SeekFrom::End(-16))?;
	f.read_exact(&mut buf)?;
	if buf != *MAGIC {
		return Err(std::io::Error::new(std::io::ErrorKind::Other, "magic mismatch"));
	}

	f.seek(SeekFrom::End(-16 - 8 - 8))?;
	let mut len_buf = [0u8; 16];
	f.read_exact(&mut len_buf)?;
	let meta_len = u64::from_le_bytes(len_buf[0..8].try_into().unwrap());
	let model_len = u64::from_le_bytes(len_buf[8..16].try_into().unwrap());

	let meta_start = file_len - 16 - 8 - 8 - meta_len;
	let model_start = meta_start - model_len;

	f.seek(SeekFrom::Start(meta_start))?;
	let mut meta_bytes = vec![0u8; meta_len as usize];
	f.read_exact(&mut meta_bytes)?;
	let meta_str = String::from_utf8_lossy(&meta_bytes).into_owned();

	f.seek(SeekFrom::Start(model_start))?;
	let mut model_bytes = vec![0u8; model_len as usize];
	f.read_exact(&mut model_bytes)?;

	Ok((meta_str, model_bytes))
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------
fn parse_meta(meta_str: &str) -> Result<(Vec<usize>, String)> {
	let meta: JsonValue = serde_json::from_str(meta_str)?;
	let shape = meta["input_shape"]
		.as_array()
		.unwrap()
		.iter()
		.map(|x| x.as_u64().unwrap() as usize)
		.collect::<Vec<_>>();
	let dtype = meta["input_dtype"].as_str().unwrap_or("f32").to_owned();
	Ok((shape, dtype))
}

fn parse_array(raw: &str, shape: &[usize]) -> Result<Vec<f32>> {
	let s = raw.trim();
	if !(s.starts_with('[') && s.ends_with(']')) {
		anyhow::bail!("Input must be '[..]'")
	}
	let inner = &s[1..s.len() - 1];
	let mut out = vec![];
	for tok in inner.split(',') {
		out.push(tok.trim().parse::<f32>()?);
	}
	let exp: usize = shape.iter().product();
	if out.len() != exp {
		anyhow::bail!("Input len {} != expected {}", out.len(), exp);
	}
	Ok(out)
}
use ort::session::SessionOutputs;
// -----------------------------------------------------------------------------
// Core inference step
// -----------------------------------------------------------------------------
fn process_input(raw: &str, input_shape: &[usize], input_dtype: &str, session: &mut Session) -> Result<()> {
    let vec_f32 = parse_array(raw, input_shape)?;

    match input_dtype {
        // ONNXRuntime will cast f32→f16 internally if needed
        "f16" | "float16" => {
            let arr = ndarray::ArrayD::<f32>::from_shape_vec(IxDyn(input_shape), vec_f32)?;
            let tensor = ort::value::Tensor::from_array(arr)?;
            let out = session.run(ort::inputs![tensor])?;
            dump_outputs(&out)?;
        }

        "i8" | "int8" => {
            let vec_i8: Vec<i8> = vec_f32.iter().map(|x| x.round() as i8).collect();
            let arr = ndarray::ArrayD::from_shape_vec(IxDyn(input_shape), vec_i8)?;
            let tensor = ort::value::Tensor::from_array(arr)?;
            let out = session.run(ort::inputs![tensor])?;
            dump_outputs(&out)?;
        }

        "u8" | "uint8" => {
            let vec_u8: Vec<u8> = vec_f32.iter().map(|x| x.round().clamp(0.0, 255.0) as u8).collect();
            let arr = ndarray::ArrayD::from_shape_vec(IxDyn(input_shape), vec_u8)?;
            let tensor = ort::value::Tensor::from_array(arr)?;
            let out = session.run(ort::inputs![tensor])?;
            dump_outputs(&out)?;
        }

        _ => {
            let arr = ndarray::ArrayD::<f32>::from_shape_vec(IxDyn(input_shape), vec_f32)?;
            let tensor = ort::value::Tensor::from_array(arr)?;
            let out = session.run(ort::inputs![tensor])?;
            dump_outputs(&out)?;
        }
    }

    Ok(())
}

// -----------------------------------------------------------------------------
// Output printing (no half::f16 anywhere)
// -----------------------------------------------------------------------------
fn dump_outputs(out: &SessionOutputs) -> Result<()> {
    for (i, (_name, val)) in out.iter().enumerate() {
        if let Ok(v) = val.try_extract_array::<f32>() {
            println!("Output[{i}] (f32): {:?}", v.as_slice().unwrap());
        } else if let Ok(v) = val.try_extract_array::<i8>() {
            println!("Output[{i}] (i8): {:?}", v.as_slice().unwrap());
        } else if let Ok(v) = val.try_extract_array::<u8>() {
            println!("Output[{i}] (u8): {:?}", v.as_slice().unwrap());
        } else if let Ok(v) = val.try_extract_array::<i32>() {
            println!("Output[{i}] (i32): {:?}", v.as_slice().unwrap());
        } else if let Ok(v) = val.try_extract_array::<f64>() {
            println!("Output[{i}] (f64): {:?}", v.as_slice().unwrap());
        } else {
            println!("Output[{i}]: [unhandled dtype]");
        }
    }
    Ok(())
}