class_name Messagepack
## Messagepack implementation for Godot 4 in GDScript
##
## You can find the full spec at: https://github.com/msgpack/msgpack/blob/master/spec.md

const FIRST3 = 0xe0
const FIRST4 = 0xf0
const LAST4 = 0x0f
const LAST5 = 0x1f
const EXT_VECTOR2 = 0x01
const EXT_VECTOR3 = 0x02
const EXT_VECTOR4 = 0x03


const types = {
	"nil": 0xc0,
	"false": 0xc2,
	"true": 0xc3,
	"positive_fixint": [0x00, 0x7f],
	"negative_fixint": [0xe0, 0xff],
	"uint_8": 0xcc,
	"uint_16": 0xcd,
	"uint_32": 0xce,
	"uint_64": 0xcf,
	"int_8": 0xd0,
	"int_16": 0xd1,
	"int_32": 0xd2,
	"int_64": 0xd3,
	"float_32": 0xca,
	"float_64": 0xcb,
	"fixstr": [0xa0, 0xbf],
	"str_8": 0xd9,
	"str_16": 0xda,
	"str_32": 0xdb,
	"fixarray": [0x90, 0x9f],
	"array_16": 0xdc,
	"array_32": 0xdd,
	"fixmap": [0x80, 0x8f],
	"map_16": 0xde,
	"map_32": 0xdf,
	"bin_8": 0xc4,
	"bin_16": 0xc5,
	"bin_32": 0xc6
}

## This function takes a Variant and encodes it according to the Messagepack spec
##
## Parameters:
##   - value: Variant to be encoded
##
## Returns:
##   A dictionary containing the status of the encoding and the value as a PackedByteArray
static func encode(value) -> Dictionary:
	var buffer = StreamPeerBuffer.new()
	buffer.set_big_endian(true)
	var err = _encode_message(buffer, value)
	return {
		value = buffer.data_array,
		status = err
	}

static func _encode_message(buffer: StreamPeerBuffer, value):
	if value is StringName: value = String(value)
	match typeof(value):
		TYPE_NIL:
			buffer.put_u8(types["nil"])

		TYPE_BOOL:
			if value == true:
				buffer.put_u8(types["true"])
			else:
				buffer.put_u8(types["false"])

		TYPE_INT:
			if - (1 << 5) <= value and value <= (1 << 7) - 1:
				buffer.put_8(value)
			elif - (1 << 7) <= value and value <= (1 << 7):
				buffer.put_u8(types["int_8"])
				buffer.put_8(value)
			elif 0 <= value and value <= (1 << 8) - 1:
				buffer.put_u8(types["uint_8"])
				buffer.put_u8(value)
			elif - (1 << 15) <= value and value <= (1 << 15):
				buffer.put_u8(types["int_16"])
				buffer.put_16(value)
			elif 0 <= value and value <= (1 << 16) - 1:
				buffer.put_u8(types["uint_16"])
				buffer.put_u16(value)
			elif - (1 << 31) <= value and value <= (1 << 31):
				buffer.put_u8(types["int_32"])
				buffer.put_32(value)
			elif 0 <= value and value <= (1 << 32) - 1:
				buffer.put_u8(types["uint_32"])
				buffer.put_u32(value)
			elif - (1 << 63) <= value and value <= (1 << 63):
				buffer.put_u8(types["int_64"])
				buffer.put_64(value)
			else:
				buffer.put_u8(types["uint_64"])
				buffer.put_u64(value)

		TYPE_FLOAT:
			buffer.put_u8(types["float_32"])
			buffer.put_float(value)

		TYPE_STRING:
			var bytes = value.to_utf8_buffer()
			var size = bytes.size()
			if size <= (1 << 5) - 1:
				buffer.put_u8(types["fixstr"][0]|size)
			elif size <= (1 << 8) - 1:
				buffer.put_u8(types["str_8"])
			elif size <= (1 << 16) - 1:
				buffer.put_u8(types["str_16"])
			elif size <= (1 << 32) - 1:
				buffer.put_u32(types["str_32"])
			else:
				printerr("Unsupported string: string is too big")
				return ERR_INVALID_DATA

			buffer.put_data(bytes)

		TYPE_ARRAY:
			var size = value.size()
			if size <= 15:
				buffer.put_u8(types["fixarray"][0]|size)
			elif size <= (1 << 16) - 1:
				buffer.put_u8(types["array_16"])
				buffer.put_u16(size)
			elif size <= (1 << 32) - 1:
				buffer.put_u8(types["array_32"])
				buffer.put_u32(size)
			else:
				printerr("Unsupported array: array is too long")
				return ERR_INVALID_DATA
			
			for obj in value:
				_encode_message(buffer, obj)

		TYPE_DICTIONARY:
			var size = value.size()
			if size <= 15:
				buffer.put_u8(types["fixmap"][0]|size)
			elif size <= (1 << 16) - 1:
				buffer.put_u8(types["map_16"])
				buffer.put_u16(size)
			elif size <= (1 << 32) - 1:
				buffer.put_u8(types["map_32"])
				buffer.put_u32(size)
			else:
				printerr("Unsupported dictionary: dictionary is too big")
				return ERR_INVALID_DATA
			
			for key in value:
				_encode_message(buffer, key)
				_encode_message(buffer, value[key])

		TYPE_VECTOR2:
			buffer.put_u8(0xd6) # fixext 4*2 = 8 bytes
			buffer.put_8(EXT_VECTOR2)
			buffer.put_float(value.x)
			buffer.put_float(value.y)
			return OK

		TYPE_VECTOR3:
			# ext8, length = 12 bytes, type = EXT_VECTOR3
			buffer.put_u8(0xc7)
			buffer.put_u8(12)   # 3 floats * 4 bytes
			buffer.put_8(EXT_VECTOR3)
			buffer.put_float(value.x)
			buffer.put_float(value.y)
			buffer.put_float(value.z)
			return OK

		TYPE_VECTOR4:
			buffer.put_u8(0xd8) # fixext 16 (16 bytes)
			buffer.put_8(EXT_VECTOR4)
			buffer.put_float(value.x)
			buffer.put_float(value.y)
			buffer.put_float(value.z)
			buffer.put_float(value.w)
			return OK

		
		TYPE_PACKED_BYTE_ARRAY:
			var size = value.size()
			if size <= (1 << 8) - 1:
				buffer.put_u8(types["bin_8"])
				buffer.put_u8(size)
			elif size <= (1 << 16) - 1:
				buffer.put_u8(types["bin_16"])
				buffer.put_u16(size)
			elif size <= (1 << 32) - 1:
				buffer.put_u8(types["bin_32"])
				buffer.put_u32(size)
			else:
				printerr("Unsupported packed byte array: packed byte array is too big")
				return ERR_INVALID_DATA
			
			buffer.put_data(value)

		_:
			printerr("Unsupported data type: %s" % (value))
			return ERR_UNAVAILABLE


## This function takes a PackedByteArray and decodes it according to the Messagepack spec
##
## Parameters:
##   - bytes: PackedByteArray to be decoded
##
## Returns:
##   A dictionary containing the status of the decoding and the value as Godot Variants
static func decode(bytes: PackedByteArray):
	var buffer = StreamPeerBuffer.new()
	buffer.set_big_endian(true)
	buffer.set_data_array(bytes)
	
	var err = {
		error = null
	}
	var message = _decode_message(buffer, err)
	return {
		value = message,
		status = err.error
	}

static func _decode_message(buffer: StreamPeerBuffer, err: Dictionary):
	var buffer_size = buffer.get_size()
	var first_byte = buffer.get_u8()
	
	if first_byte & 0x80 == 0: # positive fixint
		return first_byte
		
	elif first_byte & FIRST4 == 0x80: # fixmap
		var size = first_byte & 0x0f
		var dict = {}
		for _x in range(size):
			var key = _decode_message(buffer, err)
			var val = _decode_message(buffer, err)
			dict[key] = val
		return dict
			
	elif first_byte & FIRST4 == 0x90: # fixarray
		var size = first_byte & 0x0f
		var array = []
		for _x in range(size):
			var val = _decode_message(buffer, err)
			array.append(val)
		return array
		
	elif first_byte & FIRST3 == 0xa0: # fixstr
		var size = first_byte & 0x1f
		return buffer.get_utf8_string(size)
		
	elif first_byte == types["nil"]: # nil
		return null
		
	elif first_byte == types["false"]:
		return false
		
	elif first_byte == types["true"]:
		return true
		
	elif first_byte == types["bin_8"]:
		var length = buffer.get_u8()
		return buffer.get_partial_data(length)
		
	elif first_byte == types["bin_16"]:
		var length = buffer.get_u16()
		return buffer.get_partial_data(length)
		
	elif first_byte == types["bin_32"]:
		var length = buffer.get_u32()
		return buffer.get_partial_data(length)

	# --- CUSTOM EXTENSIONS (Vectors) ---
	elif first_byte == 0xc7: # ext8
		var length = buffer.get_u8()
		var type_code = buffer.get_8()

		match type_code:
			EXT_VECTOR2:
				if length == 8:
					return Vector2(buffer.get_float(), buffer.get_float())
			EXT_VECTOR3:
				if length == 12:
					return Vector3(buffer.get_float(), buffer.get_float(), buffer.get_float())
			EXT_VECTOR4:
				if length == 16:
					return Vector4(buffer.get_float(), buffer.get_float(), buffer.get_float(), buffer.get_float())
			_:
				printerr("Unknown ext8 subtype: %d (length=%d)" % [type_code, length])
				err.error = ERR_UNAVAILABLE
				return null

	# unused ext types
	elif first_byte == 0xc8 or first_byte == 0xc9:
		printerr("ext16/ext32 types not implemented")
		err.error = ERR_UNAVAILABLE
		return null

	elif first_byte == types["float_32"]:
		return buffer.get_float()
		
	elif first_byte == types["float_64"]:
		return buffer.get_double()
		
	elif first_byte == types["uint_8"]:
		return buffer.get_u8()
		
	elif first_byte == types["uint_16"]:
		return buffer.get_u16()
		
	elif first_byte == types["uint_32"]:
		return buffer.get_u32()
		
	elif first_byte == types["uint_64"]:
		return buffer.get_u64()
		
	elif first_byte == types["int_8"]:
		return buffer.get_8()
		
	elif first_byte == types["int_16"]:
		return buffer.get_16()
		
	elif first_byte == types["int_32"]:
		return buffer.get_32()
		
	elif first_byte == types["int_64"]:
		return buffer.get_64()
		
	elif first_byte == 0xd6: # fixext8 (Vector2 legacy)
		var type_code = buffer.get_8()
		if type_code == EXT_VECTOR2:
			return Vector2(buffer.get_float(), buffer.get_float())
		else:
			printerr("Unknown fixext8 subtype: %d" % type_code)
			err.error = ERR_UNAVAILABLE
			return null

	elif first_byte == 0xd8: # fixext16 (Vector4 legacy)
		var type_code = buffer.get_8()
		if type_code == EXT_VECTOR4:
			return Vector4(buffer.get_float(), buffer.get_float(), buffer.get_float(), buffer.get_float())
		else:
			printerr("Unknown fixext16 subtype: %d" % type_code)
			err.error = ERR_UNAVAILABLE
			return null

	elif first_byte == types["str_8"]:
		var size = buffer.get_u8()
		return buffer.get_utf8_string(size)
		
	elif first_byte == types["str_16"]:
		var size = buffer.get_u16()
		return buffer.get_utf8_string(size)
		
	elif first_byte == types["str_32"]:
		var size = buffer.get_u32()
		return buffer.get_utf8_string(size)
		
	elif first_byte == types["array_16"]:
		var length = buffer.get_u16()
		var array = []
		for _x in range(length):
			var val = _decode_message(buffer, err)
			array.append(val)
		return array
		
	elif first_byte == types["array_32"]:
		var length = buffer.get_u32()
		var array = []
		for _x in range(length):
			var val = _decode_message(buffer, err)
			array.append(val)
		return array
		
	elif first_byte == types["map_16"]:
		var length = buffer.get_u16()
		var dict = {}
		for _x in range(length):
			var key = _decode_message(buffer, err)
			var val = _decode_message(buffer, err)
			dict[key] = val
		return dict
		
	elif first_byte == types["map_32"]:
		var length = buffer.get_u32()
		var dict = {}
		for _x in range(length):
			var key = _decode_message(buffer, err)
			var val = _decode_message(buffer, err)
			dict[key] = val
		return dict
		
	elif first_byte & FIRST3 == 0xe0: # negative fixint
		return first_byte - 256
		
	else:
		printerr("Unknown header 0x%02x" % first_byte)
		err.error = ERR_UNAVAILABLE
		return null
