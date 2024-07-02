class_name ByteBuf extends RefCounted

var inner : PackedByteArray
var cursor := 0

func _init(inner: PackedByteArray):
  self.inner = inner

func read_float() -> float:
  var out := self.inner.decode_float(cursor)
  cursor += 4
  return out

func read_int() -> int:
  var out := self.inner.decode_s32(cursor)
  cursor += 4
  return out

func read_vec2() -> Vector2:
  var x := self.read_float()
  var y := self.read_float()
  return Vector2(x, y)

func read_vec3() -> Vector3:
  var x := self.read_float()
  var y := self.read_float()
  var z := self.read_float()
  return Vector3(x, y, z)

# Read a vec4 and drop a float
func read_vec3_opengl() -> Vector3:
  var out := self.read_vec3()
  self.read_float()
  return out

func read_vec4() -> Vector4:
  var x := self.read_float()
  var y := self.read_float()
  var z := self.read_float()
  var w := self.read_float()
  return Vector4(x, y, z, w)

func skip(bytes: int):
  self.cursor += bytes

func size() -> int: return self.inner.size()
func bytes_remaining() -> int: return self.size() - self.cursor
func finished() -> bool: return self.bytes_remaining() == 0
