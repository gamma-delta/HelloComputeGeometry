class_name ByteWriter extends RefCounted

var inner : PackedByteArray

func _init():
  self.inner = PackedByteArray()

func write_float(f: float):
  var sz := self.size()
  self.inner.resize(sz + 4)
  self.inner.encode_float(sz, f)

func write_int(i: int):
  var sz := self.size()
  self.inner.resize(sz + 4)
  self.inner.encode_s32(sz, i)

func write_vec2(v: Vector2):
  self.write_float(v.x)
  self.write_float(v.y)

func write_vec3(v: Vector3):
  self.write_float(v.x)
  self.write_float(v.y)
  self.write_float(v.z)

func write_vec4(v: Vector4):
  self.write_float(v.x)
  self.write_float(v.y)
  self.write_float(v.z)
  self.write_float(v.w)

func skip(bytes: int):
  self.inner.resize(self.size() + bytes)

func size() -> int: return self.inner.size()
