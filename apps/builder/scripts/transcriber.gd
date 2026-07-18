
extends WebAPI
class_name Transcriber


var mic_player: AudioStreamPlayer
var record_effect: AudioEffectRecord
var recording := false
var rec_bus_idx: int = -1


func _ready() -> void:
	if !glob.NO_TRANSCRIBER_WARMUP:
		warm_init()
	
var warmed: bool = false
func warm_init():
	warmed = true
	rec_bus_idx = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(rec_bus_idx, "RecordBus")
	AudioServer.set_bus_mute(rec_bus_idx, true)

	record_effect = AudioEffectRecord.new()
	record_effect.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(rec_bus_idx, record_effect)

	mic_player = AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = "RecordBus"
	add_child(mic_player)
	
	await get_tree().process_frame
	begin_recording()
	await get_tree().process_frame
	end_recording()
	mic_player.play()
	




var t_record: float = 0.0
var t_max: float = 0.0
func _process(delta: float) -> void:
	if recording:
		t_record += delta
		#("a")
		if t_record > t_max and t_max > 0.01:
			end_recording()
	#(record_effect.is_recording_active())


var _on_end = null
func begin_recording(thres: float = 0, on_end = null) -> void:
	if recording:
		return
	if not warmed:
		await warm_init()
	recording = true
	t_max = thres
	t_record = 0.0
	_on_end = on_end
	#("dkdk")
	record_effect.set_recording_active(true)
	#(" Recording started...")

signal recording_ended
func end_recording() -> void:
	if not recording:
		return
	if _on_end:
		_on_end.call()
	recording_ended.emit()
	recording = false

	record_effect.set_recording_active(false)

	var wav: AudioStreamWAV = record_effect.get_recording()
	buf = wav_to_buffer(wav)

	#if 1 and buf and buf.size() > 0:
		#var DEBUG_SAVE_PATH = "c:/users/mike/desktop"
		#var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
		#var file_path := "%s/recording_%s.wav" % [DEBUG_SAVE_PATH, timestamp]
		#var f := FileAccess.open(file_path, FileAccess.WRITE)
		#if f:
			#f.store_buffer(buf)
			#f.close()
			##(t_record)
			##("[DEBUG] Saved recording to: ", file_path)
		#else:
			#push_warning("Failed to open " + file_path)

	#var f := FileAccess.open(DEBUG_WAV, FileAccess.WRITE)
	#f.store_buffer(wav_to_buffer(wav))
	#f.close()

var buf = null

func wav_to_buffer(wav: AudioStreamWAV) -> PackedByteArray:
	var buf := PackedByteArray()
	if not wav: return PackedByteArray()
	var format_code := 1 # PCM
	var n_channels := 2 if wav.stereo else 1
	var sample_rate := AudioServer.get_mix_rate()
	var bytes_per_sample := 1 if wav.format == AudioStreamWAV.FORMAT_8_BITS else 2
	var data_bytes := wav.get_data().size()

	var put_str = func put_str(s: String): buf.append_array(s.to_utf8_buffer())
	var put_u16 = func put_u16(v: int): buf.append_array(PackedByteArray([v & 0xFF, (v >> 8) & 0xFF]))
	var put_u32 = func put_u32(v: int):
		buf.append_array(PackedByteArray([
			v & 0xFF, (v >> 8) & 0xFF,
			(v >> 16) & 0xFF, (v >> 24) & 0xFF
		]))

	put_str.call("RIFF")
	put_u32.call(data_bytes + 36)
	put_str.call("WAVEfmt ")
	put_u32.call(16)
	put_u16.call(format_code)
	put_u16.call(n_channels)
	put_u32.call(sample_rate)
	put_u32.call(sample_rate * n_channels * bytes_per_sample)
	put_u16.call(n_channels * bytes_per_sample)
	put_u16.call(bytes_per_sample * 8)
	put_str.call("data")
	put_u32.call(data_bytes)

	var raw := wav.get_data()
	if bytes_per_sample == 1:
		for i in raw.size():
			var s := raw[i]
			buf.append((s + 128) & 0xFF)
	else:
		for i in range(0, raw.size(), 2):
			var lo := raw[i]
			var hi := raw[i + 1]
			buf.append(lo)   # little endian: low byte first
			buf.append(hi)

	return buf

func send_recording() -> RequestHandle:
	var wav_bytes = buf

	var headers := get_headers()
	headers.erase("Content-Type: application/json")
	headers.append("Content-Type: audio/wav")
	headers.append("X-DType: wav")
	headers.append("user: n")
	headers.append("pass: 1")

	return _request_raw(api_url + "transcribe_file", wav_bytes, headers)


# ───────────────────────────────────────────────
#  INTERNAL RAW REQUEST
# ───────────────────────────────────────────────
func _request_raw(address: String, body: PackedByteArray, headers: PackedStringArray) -> RequestHandle:
	var handle := RequestHandle.new()
	handle.id = "req_%s" % str(Time.get_ticks_usec())
	add_user_signal("http_done_%s" % handle.id, ["result"])

	var req := HTTPRequest.new()
	req.timeout = 5.0
	req.use_threads = true
	add_child(req)

	var err := req.request_raw(address, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		var fail := {"ok": false, "error": err, "code": 0, "body": PackedByteArray(), "address": address, "id": handle.id}
		call_deferred("_emit_http_done", handle, fail)
		return handle

	req.request_completed.connect(func(result: int, code: int, hdrs: PackedStringArray, body: PackedByteArray):
		var json_result := {}
		if body.size() > 0:
			var text := body.get_string_from_utf8()
			json_result = JSON.parse_string(text)
		var payload := {
			"ok": code >= 200 and code < 300,
			"code": code,
			"body": json_result,
			"address": address,
			"id": handle.id
		}
		_emit_http_done(handle, payload)
		req.queue_free()
	)
	return handle
