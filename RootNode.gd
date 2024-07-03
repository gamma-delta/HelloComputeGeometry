extends Node3D

@export var MY_MESH : Mesh

var rd : RenderingDevice
var compute_stuff := {}
var draw_stuff := {}

var in_buf_scratch := PackedByteArray()
var out_buf_scratch := PackedByteArray()
var tri_count := 0

var shader_texture : Texture2DRD

const SIZE_OF_FLOAT := 4
const SIZE_OF_VERTEX := 8 * SIZE_OF_FLOAT
const SIZE_OF_TRI := SIZE_OF_VERTEX * 3 + 4 * SIZE_OF_FLOAT
const MAX_GENERATED_TRIS_PER_TRI := 4

const TEXTURE_SIZE := 512 # a guess

# Called when the node enters the scene tree for the first time.
func _ready():
  RenderingServer.call_on_render_thread(self.init_gpu)
  
  var screen := $Screen as MeshInstance3D
  var mat := screen.get_active_material(0) as ShaderMaterial
  self.shader_texture = Texture2DRD.new()
  mat.set_shader_parameter("data_in", self.shader_texture)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
  var mesh_data := format_mesh(self.MY_MESH, self.in_buf_scratch)
  self.tri_count = mesh_data["tri_count"]
  self.out_buf_scratch.resize(self.in_buf_scratch.size() * MAX_GENERATED_TRIS_PER_TRI)

  # This is the "Secret sauce"
  # This makes the Godot texture read from the .gdshader and the GLSL texture
  # written from the .compute.glsl be the same image
  self.shader_texture.texture_rd_rid = self.compute_stuff["out_tex_rid"]

  RenderingServer.call_on_render_thread(self.compute_frame)

func init_gpu():
  self.rd = RenderingServer.get_rendering_device()
  self.init_compute()

func init_compute():
  var shader_file := load("res://shaders/pyramidize.compute.glsl")
  var shader_spirv : RDShaderSPIRV = shader_file.get_spirv()
  var shader_rid := rd.shader_create_from_spirv(shader_spirv)
  
  var format := format_mesh(self.MY_MESH, self.in_buf_scratch)
  self.tri_count = format["tri_count"]
  self.out_buf_scratch.resize(self.in_buf_scratch.size() * MAX_GENERATED_TRIS_PER_TRI)
  var in_buf_rid := self.rd.storage_buffer_create(self.in_buf_scratch.size(), self.in_buf_scratch)
  
  var tex_format := RDTextureFormat.new()
  tex_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
  tex_format.width = TEXTURE_SIZE
  tex_format.height = TEXTURE_SIZE
  tex_format.depth = 1
  tex_format.usage_bits = \
      RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
    | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
    | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
    | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
    | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
  tex_format.mipmaps = 1
  tex_format.samples = RenderingDevice.TEXTURE_SAMPLES_1
  var out_tex_rid := self.rd.texture_create(tex_format, RDTextureView.new())
  self.rd.texture_clear(out_tex_rid, Color.TRANSPARENT, 0, 1, 0, 1)
  
  var in_buf_uniform := RDUniform.new()
  in_buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
  in_buf_uniform.binding = 0 # lines up with the binding=0 in the glsl
  in_buf_uniform.add_id(in_buf_rid)
  var out_tex_uniform := RDUniform.new()
  out_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
  out_tex_uniform.binding = 1
  out_tex_uniform.add_id(out_tex_rid)
  
  # the 0 lines up with the set=0 in glsl
  var uniform_set := rd.uniform_set_create([
    in_buf_uniform, out_tex_uniform
  ], shader_rid, 0)
  var pipeline := rd.compute_pipeline_create(shader_rid)
  assert(pipeline.is_valid())

  self.compute_stuff["shader_rid"] = shader_rid
  self.compute_stuff["in_buf_rid"] = in_buf_rid
  self.compute_stuff["out_tex_rid"] = out_tex_rid
  self.compute_stuff["uniform_set"] = uniform_set
  self.compute_stuff["pipeline"] = pipeline

func compute_frame():
  rd.buffer_update(self.compute_stuff["in_buf_rid"], 0, self.in_buf_scratch.size(), self.in_buf_scratch)
  
  rd.texture_clear(self.compute_stuff["out_tex_rid"], Color.TRANSPARENT, 0, 1, 0, 1)

  var compute_list := rd.compute_list_begin()
  rd.compute_list_bind_compute_pipeline(compute_list, self.compute_stuff["pipeline"])
  rd.compute_list_bind_uniform_set(compute_list, self.compute_stuff["uniform_set"], 0)
  
  var push_list := ByteWriter.new()
  push_list.write_int(TEXTURE_SIZE)
  push_list.write_int(TEXTURE_SIZE)
  push_list.write_float(Time.get_ticks_msec() / 1_000.0)
  push_list.skip(4)
  #print(push_list.inner)
  rd.compute_list_set_push_constant(compute_list, push_list.inner, push_list.size())
  # set up the dispatch!
  # In the shader, I've set up a local size of 32
  var needed_dispatch_count : int = self.tri_count / 32
  rd.compute_list_dispatch(compute_list, needed_dispatch_count, 1, 1)
  rd.compute_list_end()

static func format_mesh(mesh: Mesh, tris_buf: PackedByteArray) -> Dictionary:
  var surf1 := mesh.surface_get_arrays(0)
  var vertices : PackedVector3Array = surf1[Mesh.ARRAY_VERTEX]
  var normals : PackedVector3Array = surf1[Mesh.ARRAY_NORMAL]  
  var uvs : PackedVector2Array = surf1[Mesh.ARRAY_TEX_UV]
  var indices : PackedInt32Array = surf1[Mesh.ARRAY_INDEX]
  print("mesh vert count:", vertices.size(), "; idx count:", indices.size())
  
  tris_buf.clear()
  # we have to de-index the array here.
  for i in range(0, indices.size()):
    var index := indices[i]
    var vert := vertices[index]
    var norm := normals[index]
    var uv := uvs[index]

    # Must be laid out the same as in the glsl
    var float_arr := PackedFloat32Array([
      vert.x, vert.y, vert.z, 0.0,
      norm.x, norm.y, norm.z, 0.0,
      uv.x, uv.y,
      0.0, 0.0])
    tris_buf.append_array(float_arr.to_byte_array())
  
  return {"tri_count" = indices.size() / 3}
