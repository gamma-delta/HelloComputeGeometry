extends Node3D

@export var MY_MESH : Mesh

var rd : RenderingDevice
var compute_stuff := {}
var draw_stuff := {}

var in_buf_scratch := PackedByteArray()
var out_buf_scratch := PackedByteArray()

const SIZE_OF_FLOAT := 4
const SIZE_OF_VERTEX := 8 * SIZE_OF_FLOAT
const SIZE_OF_TRI := SIZE_OF_VERTEX * 3 + 4 * SIZE_OF_FLOAT
const MAX_GENERATED_TRIS_PER_TRI := 1

# Called when the node enters the scene tree for the first time.
func _ready():
  pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
  if self.rd == null:
    self.init_gpu()

  var mesh_data := format_mesh(self.MY_MESH, self.in_buf_scratch)

  self.out_buf_scratch.resize(self.in_buf_scratch.size() * MAX_GENERATED_TRIS_PER_TRI)
  rd.buffer_update(self.compute_stuff["in_buf_rid"], 0, self.in_buf_scratch.size(), self.in_buf_scratch)
  
  var misc_buf := PackedByteArray()
  misc_buf.append_array(PackedFloat32Array([Time.get_unix_time_from_system()]).to_byte_array())
  rd.buffer_update(self.compute_stuff["misc_buf_rid"], 0, misc_buf.size(), misc_buf)

  var compute_list := rd.compute_list_begin()
  rd.compute_list_bind_compute_pipeline(compute_list, self.compute_stuff["pipeline"])
  rd.compute_list_bind_uniform_set(compute_list, self.compute_stuff["uniform_set"], 0)
  # set up the dispatch!
  # In the shader, I've set up a local size of 32
  var needed_dispatch_count : int = mesh_data["tri_count"] / 32
  rd.compute_list_dispatch(compute_list, needed_dispatch_count, 1, 1)
  rd.compute_list_end()
  
  var draw_rd := RenderingServer.get_rendering_device()
  # this crashes on older versions of godot
  # see: https://github.com/godotengine/godot/issues/88580
  var draw_list := draw_rd.draw_list_begin_for_screen()
  draw_rd.draw_list_bind_render_pipeline(draw_list, self.draw_stuff["pipeline"])
  draw_rd.draw_list_bind_uniform_set(draw_list, self.draw_stuff["uniform_set"], 0)
  draw_rd.draw_list_bind_vertex_array(draw_list)
  draw_rd.draw_list_draw(draw_list, false, 0, 3)
  draw_rd.draw_list_end()

func init_gpu():
  self.rd = RenderingServer.get_rendering_device()
  self.init_compute()
  self.init_draw()

func init_compute():
  var shader_file := load("res://pyramidize.compute.glsl")
  var shader_spirv : RDShaderSPIRV = shader_file.get_spirv()
  var shader_rid := rd.shader_create_from_spirv(shader_spirv)
  
  var format := format_mesh(self.MY_MESH, self.in_buf_scratch)
  self.out_buf_scratch.resize(self.in_buf_scratch.size() * MAX_GENERATED_TRIS_PER_TRI)
  var in_buf_rid := self.rd.storage_buffer_create(self.in_buf_scratch.size(), self.in_buf_scratch)
  var out_buf_rid := self.rd.storage_buffer_create(self.out_buf_scratch.size(), self.out_buf_scratch)
  var misc_buf_rid := self.rd.storage_buffer_create(4)
  
  var in_buf_uniform := RDUniform.new()
  in_buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
  in_buf_uniform.binding = 0 # lines up with the binding=0 in the glsl
  in_buf_uniform.add_id(in_buf_rid)
  var out_buf_uniform := RDUniform.new()
  out_buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
  out_buf_uniform.binding = 1
  out_buf_uniform.add_id(out_buf_rid)
  var misc_buf_uniform := RDUniform.new()
  misc_buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
  misc_buf_uniform.binding = 2
  misc_buf_uniform.add_id(misc_buf_rid)
  
  # the 0 lines up with the set=0 in glsl
  var uniform_set := rd.uniform_set_create([
    in_buf_uniform, out_buf_uniform, misc_buf_uniform
  ], shader_rid, 0)
  var pipeline := rd.compute_pipeline_create(shader_rid)

  self.compute_stuff["shader_rid"] = shader_rid
  self.compute_stuff["in_buf_rid"] = in_buf_rid
  self.compute_stuff["out_buf_rid"] = out_buf_rid
  self.compute_stuff["misc_buf_rid"] = misc_buf_rid
  self.compute_stuff["uniform_set"] = uniform_set
  self.compute_stuff["pipeline"] = pipeline

func init_draw():
  var rd := RenderingServer.get_rendering_device()
  var shader_file := load("res://pyramidize.glsl")
  var shader_spirv : RDShaderSPIRV = shader_file.get_spirv()
  var shader_rid := rd.shader_create_from_spirv(shader_spirv)
  
  var dummy_verts_buf = PackedFloat32Array([
    0, 0, 0, 0,
    1, 0, 0, 0,
    0, 1, 0, 0,
  ]).to_byte_array()
  var verts_buf_rid := rd.storage_buffer_create(dummy_verts_buf.size(), dummy_verts_buf)

  var dummy_verts_array_rid := rd.vertex_array_create(3,
    RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,
    dummy_verts_buf)
  
  var vert_buf_uniform := RDUniform.new()
  vert_buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER  
  vert_buf_uniform.binding = 0
  vert_buf_uniform.add_id(verts_buf_rid)
  #var misc_buf_uniform := RDUniform.new()
  #misc_buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
  #misc_buf_uniform.binding = 0
  #misc_buf_uniform.add_id(misc_buf_rid)
  
  var uniform_set := rd.uniform_set_create([
    vert_buf_uniform, #misc_buf_uniform
  ], shader_rid, 0)
      
  # https://github.com/godotengine/godot/issues/78514
  # https://github.com/godotengine/godot/blob/f0d15bbfdfde1c1076903afb7a7db373580d5534/servers/rendering/rendering_device.cpp#L6559
  # Much of this is not documented, but the comments in the src code are good
  # thanks, godot engine comment writers!
  var blend := RDPipelineColorBlendState.new()
  blend.attachments.push_back(RDPipelineColorBlendStateAttachment.new())
  
  # you can use zero formats here to not care about formats
  # because we're supplying the verts ourself, that works
  var pipeline := rd.render_pipeline_create(shader_rid, 
    # spent a long time looking for this, turns out there's just a fn for it!
    rd.screen_get_framebuffer_format(),
    RenderingDevice.INVALID_ID,
    RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, 
    RDPipelineRasterizationState.new(),
    RDPipelineMultisampleState.new(),
    RDPipelineDepthStencilState.new(),
    blend)
  assert(pipeline.is_valid())
  
  self.draw_stuff["shader_rid"] = shader_rid
  # self.draw_stuff["misc_buf_rid"] = misc_buf_rid
  self.draw_stuff["verts_buf_rid"] = verts_buf_rid
  self.draw_stuff["uniform_set"] = uniform_set
  self.draw_stuff["pipeline"] = pipeline

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
