package vulkan_renderer

import vk "vendor:vulkan"
import "vendor:glfw"

import "core:log"

@(rodata)
vertex_shader_bytecode := #load("shader_vert.spv")
@(rodata)
fragment_shader_bytecode := #load("shader_frag.spv")

Renderer :: struct {
	instance: vk.Instance,
	debug_utils_messenger: vk.DebugUtilsMessengerEXT,

	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	graphics_queue_family_index: u32,
	graphics_queue: vk.Queue,
	presentation_queue_family_index: u32,
	presentation_queue: vk.Queue,

	surface: vk.SurfaceKHR,
	swap_chain: vk.SwapchainKHR,
	swap_chain_images: [dynamic]vk.Image,
	swap_chain_image_views: [dynamic]vk.ImageView,
	swap_chain_image_format: vk.Format,
	swap_chain_extent: vk.Extent2D,

	render_pass: vk.RenderPass,
	pipeline_layout: vk.PipelineLayout,
	pipeline: vk.Pipeline,
	framebuffers: [dynamic]vk.Framebuffer,

	command_pool: vk.CommandPool,
	command_buffer: vk.CommandBuffer,

	image_available_semaphore: vk.Semaphore,
	render_finished_semaphore: vk.Semaphore,
	in_flight_fence: vk.Fence,
}

Swap_Chain_Properties :: struct {
	surface_capabilities: vk.SurfaceCapabilitiesKHR,
	surface_format: vk.SurfaceFormatKHR,
	presentation_mode: vk.PresentModeKHR,
	extent: vk.Extent2D,
}

init_renderer :: proc(renderer: ^Renderer,
		      application_name: cstring,
		      window: glfw.WindowHandle) -> (ok := false) {
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
	assert(vk.CreateInstance != nil, "Vulkan function pointers not loaded")

	layers := get_vulkan_layers()
	defer delete(layers)
	instance_extensions := get_vulkan_instance_extensions()
	defer delete(instance_extensions)
	device_extensions := get_vulkan_device_extensions()
	defer delete(device_extensions)

	init_renderer_instance(renderer, application_name, layers[:], instance_extensions[:]) or_return
	defer if !ok do deinit_renderer_instance(renderer^)
	swap_chain_properties := init_renderer_device(renderer, window, layers[:], device_extensions[:]) or_return
	defer if !ok do deinit_renderer_device(renderer^)
	init_renderer_swap_chain(renderer, swap_chain_properties) or_return
	defer if !ok do deinit_renderer_swap_chain(renderer^)
	init_renderer_render_pass(renderer) or_return
	defer if !ok do deinit_renderer_render_pass(renderer^)
	init_renderer_graphics_pipeline(renderer) or_return
	defer if !ok do deinit_renderer_graphics_pipeline(renderer^)
	init_renderer_framebuffers(renderer) or_return
	defer if !ok do deinit_renderer_framebuffers(renderer^)
	init_renderer_command_buffer(renderer) or_return
	defer if !ok do deinit_renderer_command_buffer(renderer^)
	init_renderer_synchronization_primitives(renderer) or_return
	defer if !ok do deinit_renderer_synchronization_primitives(renderer^)

	ok = true
	return
}

deinit_renderer :: proc(renderer: Renderer) {
	vk.DeviceWaitIdle(renderer.device)

	deinit_renderer_synchronization_primitives(renderer)
	deinit_renderer_command_buffer(renderer)
	deinit_renderer_framebuffers(renderer)
	deinit_renderer_graphics_pipeline(renderer)
	deinit_renderer_render_pass(renderer)
	deinit_renderer_swap_chain(renderer)
	deinit_renderer_device(renderer)
	deinit_renderer_instance(renderer)
}

@(private="file")
init_renderer_instance :: proc(renderer: ^Renderer,
			       application_name: cstring,
			       instance_layers: []cstring,
			       instance_extensions: []cstring) -> (ok := false) {
	application_info := vk.ApplicationInfo {
		sType = .APPLICATION_INFO,
		pApplicationName = application_name,
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName = "No Engine",
		engineVersion = vk.MAKE_VERSION(1, 0, 0),
		apiVersion = vk.API_VERSION_1_0,
	}

	instance_debug_messenger_create_info := get_vk_debug_messenger_create_info()
	instance_create_info := vk.InstanceCreateInfo {
		sType = .INSTANCE_CREATE_INFO,
		pNext = &instance_debug_messenger_create_info,
		pApplicationInfo = &application_info,
		enabledLayerCount = cast(u32)len(instance_layers),
		ppEnabledLayerNames = raw_data(instance_layers),
		enabledExtensionCount = cast(u32)len(instance_extensions),
		ppEnabledExtensionNames = raw_data(instance_extensions),
	}

	if vk.CreateInstance(&instance_create_info, nil, &renderer.instance) != .SUCCESS do return
	defer if !ok do vk.DestroyInstance(renderer.instance, nil)
	vk.load_proc_addresses_instance(renderer.instance)

	{
		supported_extension_count: u32
		vk.EnumerateInstanceExtensionProperties(nil, &supported_extension_count, nil)
		supported_extensions := make([dynamic]vk.ExtensionProperties, supported_extension_count)
		defer delete(supported_extensions)
		vk.EnumerateInstanceExtensionProperties(nil, &supported_extension_count, raw_data(supported_extensions))

		log.infof("Supported extensions:")
		for &extension in supported_extensions do log.infof("\t%v", cast(cstring)raw_data(&extension.extensionName))
		log.info()
	}

	{
		supported_layer_count: u32
		vk.EnumerateInstanceLayerProperties(&supported_layer_count, nil)
		supported_layers := make([dynamic]vk.LayerProperties, supported_layer_count)
		defer delete(supported_layers)
		vk.EnumerateInstanceLayerProperties(&supported_layer_count, raw_data(supported_layers))

		log.infof("Supported layers:")
		for &layer in supported_layers do log.infof("\t%v", cast(cstring)raw_data(&layer.layerName))
		log.info()
	}

	when ODIN_DEBUG {
		debug_utils_messenger_create_info := get_vk_debug_messenger_create_info()
		if vk.CreateDebugUtilsMessengerEXT(renderer.instance,
						   &debug_utils_messenger_create_info,
						   nil,
						   &renderer.debug_utils_messenger) != .SUCCESS { return }
		defer if !ok do vk.DestroyDebugUtilsMessengerEXT(renderer.instance, renderer.debug_utils_messenger, nil)
	}

	ok = true
	return
}

@(private="file")
deinit_renderer_instance :: proc(renderer: Renderer) {
	when ODIN_DEBUG { vk.DestroyDebugUtilsMessengerEXT(renderer.instance, renderer.debug_utils_messenger, nil) }
	vk.DestroyInstance(renderer.instance, nil)
}

@(private="file")
init_renderer_device :: proc(renderer: ^Renderer,
			     window: glfw.WindowHandle,
			     layers: []cstring,
			     extensions: []cstring) -> (swap_chain_properties: Swap_Chain_Properties, ok := false) {
	if glfw.CreateWindowSurface(renderer.instance, window, nil, &renderer.surface) != .SUCCESS do return
	defer if !ok do vk.DestroySurfaceKHR(renderer.instance, renderer.surface, nil)

	physical_device_count: u32
	vk.EnumeratePhysicalDevices(renderer.instance, &physical_device_count, nil)
	if physical_device_count == 0 do return
	physical_devices := make([dynamic]vk.PhysicalDevice, physical_device_count)
	defer delete(physical_devices)
	vk.EnumeratePhysicalDevices(renderer.instance, &physical_device_count, raw_data(physical_devices))

	suitable_physical_device_found := false
	for &device in physical_devices {
		device_suitable := false
		swap_chain_properties, device_suitable = try_physical_device(device,
									     extensions,
									     window,
									     renderer.surface)
		if device_suitable {
			renderer.physical_device = device
			suitable_physical_device_found = true
			break
		}
	}
	if !suitable_physical_device_found do return

	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(renderer.physical_device, &queue_family_count, nil)
	queue_families := make([dynamic]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)
	vk.GetPhysicalDeviceQueueFamilyProperties(renderer.physical_device, &queue_family_count, raw_data(queue_families))

	graphics_queue_family_index_found, presentation_queue_family_index_found := false, false
	for &queue_family, queue_index in queue_families {
		if .GRAPHICS in queue_family.queueFlags {
			renderer.graphics_queue_family_index = u32(queue_index)
			graphics_queue_family_index_found = true
		}

		presentation_support: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(renderer.physical_device,
						      u32(queue_index),
						      renderer.surface,
						      &presentation_support)

		if presentation_support {
			renderer.presentation_queue_family_index = u32(queue_index)
			presentation_queue_family_index_found = true
		}

		if graphics_queue_family_index_found && presentation_queue_family_index_found do break
	}
	if !graphics_queue_family_index_found || !presentation_queue_family_index_found do return

	queue_create_infos := make([dynamic]vk.DeviceQueueCreateInfo, 0, 2)
	defer delete(queue_create_infos)

	queue_priorities := [?]f32{ 1 }
	append(&queue_create_infos, vk.DeviceQueueCreateInfo {
		sType = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = renderer.graphics_queue_family_index,
		queueCount = 1,
		pQueuePriorities = raw_data(&queue_priorities),
	})

	if renderer.graphics_queue_family_index != renderer.presentation_queue_family_index {
		append(&queue_create_infos, vk.DeviceQueueCreateInfo {
			sType = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = renderer.presentation_queue_family_index,
			queueCount = 1,
			pQueuePriorities = raw_data(&queue_priorities),
		})
	}

	physical_device_features := vk.PhysicalDeviceFeatures{}

	device_create_info := vk.DeviceCreateInfo {
		sType = .DEVICE_CREATE_INFO,
		pQueueCreateInfos = raw_data(queue_create_infos),
		queueCreateInfoCount = cast(u32)len(queue_create_infos),
		pEnabledFeatures = &physical_device_features,
		enabledLayerCount = cast(u32)len(layers),
		ppEnabledLayerNames = raw_data(layers),
		enabledExtensionCount = cast(u32)len(extensions),
		ppEnabledExtensionNames = raw_data(extensions),
	}

	if vk.CreateDevice(renderer.physical_device, &device_create_info, nil, &renderer.device) != .SUCCESS do return
	defer if !ok do vk.DestroyDevice(renderer.device, nil)
	vk.GetDeviceQueue(renderer.device, renderer.graphics_queue_family_index, 0, &renderer.graphics_queue)
	vk.GetDeviceQueue(renderer.device, renderer.presentation_queue_family_index, 0, &renderer.presentation_queue)

	ok = true
	return
}

@(private="file")
deinit_renderer_device :: proc(renderer: Renderer) {
	vk.DestroyDevice(renderer.device, nil)
	vk.DestroySurfaceKHR(renderer.instance, renderer.surface, nil)
}

@(private="file")
init_renderer_swap_chain :: proc(renderer: ^Renderer,
				 swap_chain_properties: Swap_Chain_Properties) -> (ok := false) {
	swap_chain_min_image_count := swap_chain_properties.surface_capabilities.minImageCount
	swap_chain_max_image_count := swap_chain_properties.surface_capabilities.maxImageCount
	wanted_swap_chain_image_count := swap_chain_min_image_count + 1
	if swap_chain_max_image_count != 0 {
		wanted_swap_chain_image_count = min(wanted_swap_chain_image_count, swap_chain_max_image_count)
	}

	queue_family_indices := [2]u32{
		renderer.graphics_queue_family_index,
		renderer.presentation_queue_family_index
	}

	swap_chain_image_sharing_mode: vk.SharingMode =
		.CONCURRENT if renderer.graphics_queue_family_index != renderer.presentation_queue_family_index else .EXCLUSIVE

	swap_chain_create_info := vk.SwapchainCreateInfoKHR {
		sType = .SWAPCHAIN_CREATE_INFO_KHR,
		surface = renderer.surface,
		minImageCount = wanted_swap_chain_image_count,
		imageFormat = swap_chain_properties.surface_format.format,
		imageColorSpace = swap_chain_properties.surface_format.colorSpace,
		imageExtent = swap_chain_properties.extent,
		imageArrayLayers = 1,
		imageUsage = { .COLOR_ATTACHMENT },
		imageSharingMode = swap_chain_image_sharing_mode,
		queueFamilyIndexCount = len(queue_family_indices),
		pQueueFamilyIndices = raw_data(&queue_family_indices),
		preTransform = swap_chain_properties.surface_capabilities.currentTransform,
		compositeAlpha = { .OPAQUE },
		presentMode = swap_chain_properties.presentation_mode,
		clipped = true,
	}

	if vk.CreateSwapchainKHR(renderer.device, &swap_chain_create_info, nil, &renderer.swap_chain) != .SUCCESS do return
	defer if !ok do vk.DestroySwapchainKHR(renderer.device, renderer.swap_chain, nil)

	swap_chain_image_count: u32
	vk.GetSwapchainImagesKHR(renderer.device, renderer.swap_chain, &swap_chain_image_count, nil)
	renderer.swap_chain_images = make([dynamic]vk.Image, swap_chain_image_count)
	vk.GetSwapchainImagesKHR(renderer.device, renderer.swap_chain, &swap_chain_image_count, raw_data(renderer.swap_chain_images))
	defer if !ok do delete(renderer.swap_chain_images)

	renderer.swap_chain_image_format = swap_chain_properties.surface_format.format
	renderer.swap_chain_extent = swap_chain_properties.extent

	renderer.swap_chain_image_views = make([dynamic]vk.ImageView, 0, len(renderer.swap_chain_images))
	defer if !ok do destroy_image_views(renderer.device, renderer.swap_chain_image_views[:])
	defer if !ok do delete(renderer.swap_chain_image_views)
	for image in renderer.swap_chain_images {
		image_view_create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = image,
			viewType = .D2,
			format = renderer.swap_chain_image_format,
			components = { .IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY },
			subresourceRange = {
				aspectMask = { .COLOR },
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}
		image_view: vk.ImageView
		if vk.CreateImageView(renderer.device, &image_view_create_info, nil, &image_view) != .SUCCESS do return
		append(&renderer.swap_chain_image_views, image_view)
	}
	assert(len(renderer.swap_chain_images) == len(renderer.swap_chain_image_views))

	ok = true
	return
}

@(private="file")
deinit_renderer_swap_chain :: proc(renderer: Renderer) {
	destroy_image_views(renderer.device, renderer.swap_chain_image_views[:])
	delete(renderer.swap_chain_image_views)
	delete(renderer.swap_chain_images)
	vk.DestroySwapchainKHR(renderer.device, renderer.swap_chain, nil)
}

@(private="file")
init_renderer_render_pass :: proc(renderer: ^Renderer) -> (ok := false) {
	color_attachment_description := vk.AttachmentDescription {
		format = renderer.swap_chain_image_format,
		samples = { ._1 },
		loadOp = .CLEAR,
		storeOp = .STORE,
		stencilLoadOp = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout = .UNDEFINED,
		finalLayout = .PRESENT_SRC_KHR,
	}

	color_attachment_ref := vk.AttachmentReference {
		attachment = 0,
		layout = .COLOR_ATTACHMENT_OPTIMAL,
	}

	subpass_description := vk.SubpassDescription {
		pipelineBindPoint = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment_ref,
	}

	subpass_dependency := vk.SubpassDependency {
		srcSubpass = vk.SUBPASS_EXTERNAL,
		dstSubpass = 0,
		srcStageMask = { .COLOR_ATTACHMENT_OUTPUT },
		srcAccessMask = {},
		dstStageMask = { .COLOR_ATTACHMENT_OUTPUT },
		dstAccessMask = { .COLOR_ATTACHMENT_WRITE },
	}

	render_pass_create_info := vk.RenderPassCreateInfo {
		sType = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments = &color_attachment_description,
		subpassCount = 1,
		pSubpasses = &subpass_description,
		dependencyCount = 1,
		pDependencies = &subpass_dependency,
	}

	if vk.CreateRenderPass(renderer.device, &render_pass_create_info, nil, &renderer.render_pass) != .SUCCESS do return
	defer if !ok do vk.DestroyRenderPass(renderer.device, renderer.render_pass, nil)

	ok = true
	return
}

@(private="file")
deinit_renderer_render_pass :: proc(renderer: Renderer) {
	vk.DestroyRenderPass(renderer.device, renderer.render_pass, nil)
}

@(private="file")
init_renderer_graphics_pipeline :: proc(renderer: ^Renderer) -> (ok := false) {
	vertex_shader_module := create_shader_module(renderer.device, vertex_shader_bytecode) or_return
	defer destroy_shader_module(renderer.device, vertex_shader_module)
	fragment_shader_module := create_shader_module(renderer.device, fragment_shader_bytecode) or_return
	defer destroy_shader_module(renderer.device, fragment_shader_module)

	pipeline_shader_stage_create_infos := [2]vk.PipelineShaderStageCreateInfo {
		vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = { .VERTEX },
			module = vertex_shader_module,
			pName = "main",
		},
		vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = { .FRAGMENT },
			module = fragment_shader_module,
			pName = "main",
		},
	}

	pipeline_vertex_input_state_create_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount = 0,
		pVertexBindingDescriptions = nil,
		vertexAttributeDescriptionCount = 0,
		pVertexAttributeDescriptions = nil,
	}

	pipeline_input_assembly_state_create_info := vk.PipelineInputAssemblyStateCreateInfo {
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	pipeline_viewport_state_create_info := vk.PipelineViewportStateCreateInfo {
		sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		pViewports = nil,
		scissorCount = 1,
		pScissors = nil,
	}

	pipeline_rasterization_state_create_info := vk.PipelineRasterizationStateCreateInfo {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable = false,
		rasterizerDiscardEnable = false,
		polygonMode = .FILL,
		lineWidth = 1,
		cullMode = { .BACK },
		frontFace = .CLOCKWISE,
		depthBiasEnable = false,
	}

	pipeline_multisample_state_create_info := vk.PipelineMultisampleStateCreateInfo {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable = false,
		rasterizationSamples = { ._1 },
	}

	pipeline_color_blend_attachment_state := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = { .R, .G, .B, .A },
		blendEnable = false,
	}

	pipeline_color_blend_state_create_info := vk.PipelineColorBlendStateCreateInfo {
		sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments = &pipeline_color_blend_attachment_state,
	}

	dynamic_states := [2]vk.DynamicState { .VIEWPORT, .SCISSOR }
	pipeline_dynamic_state_create_info := vk.PipelineDynamicStateCreateInfo {
		sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = cast(u32)len(dynamic_states),
		pDynamicStates = raw_data(&dynamic_states),
	}

	pipeline_layout_create_info := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
	}

	if vk.CreatePipelineLayout(renderer.device,
				   &pipeline_layout_create_info,
				   nil,
				   &renderer.pipeline_layout) != .SUCCESS {
		return
	}
	defer if !ok do vk.DestroyPipelineLayout(renderer.device, renderer.pipeline_layout, nil)

	graphics_pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount = cast(u32)len(pipeline_shader_stage_create_infos),
		pStages = raw_data(&pipeline_shader_stage_create_infos),
		pVertexInputState = &pipeline_vertex_input_state_create_info,
		pInputAssemblyState = &pipeline_input_assembly_state_create_info,
		pViewportState = &pipeline_viewport_state_create_info,
		pRasterizationState = &pipeline_rasterization_state_create_info,
		pMultisampleState = &pipeline_multisample_state_create_info,
		pDepthStencilState = nil,
		pColorBlendState = &pipeline_color_blend_state_create_info,
		pDynamicState = &pipeline_dynamic_state_create_info,
		layout = renderer.pipeline_layout,
		renderPass = renderer.render_pass,
		subpass = 0,
	}

	if vk.CreateGraphicsPipelines(device = renderer.device,
				      pipelineCache = 0,
				      createInfoCount = 1,
				      pCreateInfos = &graphics_pipeline_create_info,
				      pAllocator = nil,
				      pPipelines = &renderer.pipeline) != .SUCCESS {
		return
	}
	defer if !ok do vk.DestroyPipeline(renderer.device, renderer.pipeline, nil)

	ok = true
	return
}

@(private="file")
deinit_renderer_graphics_pipeline :: proc(renderer: Renderer) {
	vk.DestroyPipeline(renderer.device, renderer.pipeline, nil)
	vk.DestroyPipelineLayout(renderer.device, renderer.pipeline_layout, nil)
}

@(private="file")
init_renderer_framebuffers :: proc(renderer: ^Renderer) -> (ok := false) {
	renderer.framebuffers = make([dynamic]vk.Framebuffer, 0, len(renderer.swap_chain_images))
	defer if !ok do destroy_framebuffers(renderer.device, renderer.framebuffers[:])
	defer if !ok do delete(renderer.framebuffers)

	for &image_view in renderer.swap_chain_image_views {
		framebuffer_create_info := vk.FramebufferCreateInfo {
			sType = .FRAMEBUFFER_CREATE_INFO,
			renderPass = renderer.render_pass,
			attachmentCount = 1,
			pAttachments = &image_view,
			width = renderer.swap_chain_extent.width,
			height = renderer.swap_chain_extent.height,
			layers = 1,
		}

		framebuffer: vk.Framebuffer
		if vk.CreateFramebuffer(renderer.device, &framebuffer_create_info, nil, &framebuffer) != .SUCCESS {
			return
		}
		append(&renderer.framebuffers, framebuffer)
	}

	assert(len(renderer.framebuffers) == len(renderer.swap_chain_images))
	assert(len(renderer.framebuffers) == len(renderer.swap_chain_image_views))

	ok = true
	return
}

@(private="file")
deinit_renderer_framebuffers :: proc(renderer: Renderer) {
	destroy_framebuffers(renderer.device, renderer.framebuffers[:])
	delete(renderer.framebuffers)
}

@(private="file")
init_renderer_command_buffer :: proc(renderer: ^Renderer) -> (ok := false) {
	command_pool_create_info := vk.CommandPoolCreateInfo {
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = { .RESET_COMMAND_BUFFER },
		queueFamilyIndex = renderer.graphics_queue_family_index,
	}

	if vk.CreateCommandPool(renderer.device, &command_pool_create_info, nil, &renderer.command_pool) != .SUCCESS {
		return
	}
	defer if !ok do vk.DestroyCommandPool(renderer.device, renderer.command_pool, nil)

	command_buffer_allocate_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = renderer.command_pool,
		level = .PRIMARY,
		commandBufferCount = 1,
	}

	if vk.AllocateCommandBuffers(renderer.device, &command_buffer_allocate_info, &renderer.command_buffer) != .SUCCESS {
		return
	}

	ok = true
	return
}

@(private="file")
deinit_renderer_command_buffer :: proc(renderer: Renderer) {
	vk.DestroyCommandPool(renderer.device, renderer.command_pool, nil)
}

@(private="file")
init_renderer_synchronization_primitives :: proc(renderer: ^Renderer) -> (ok := false) {
	semaphore_create_info := vk.SemaphoreCreateInfo { sType = .SEMAPHORE_CREATE_INFO }
	if vk.CreateSemaphore(renderer.device, &semaphore_create_info, nil, &renderer.image_available_semaphore) != .SUCCESS {
		return
	}
	defer if !ok do vk.DestroySemaphore(renderer.device, renderer.image_available_semaphore, nil)

	if vk.CreateSemaphore(renderer.device, &semaphore_create_info, nil, &renderer.render_finished_semaphore) != .SUCCESS {
		return
	}
	defer if !ok do vk.DestroySemaphore(renderer.device, renderer.render_finished_semaphore, nil)

	fence_create_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = { .SIGNALED },
	}
	if vk.CreateFence(renderer.device, &fence_create_info, nil, &renderer.in_flight_fence) != .SUCCESS do return
	defer if !ok do vk.DestroyFence(renderer.device, renderer.in_flight_fence, nil)

	ok = true
	return
}

@(private="file")
deinit_renderer_synchronization_primitives :: proc(renderer: Renderer) {
	vk.DestroySemaphore(renderer.device, renderer.image_available_semaphore, nil)
	vk.DestroySemaphore(renderer.device, renderer.render_finished_semaphore, nil)
	vk.DestroyFence(renderer.device, renderer.in_flight_fence, nil)
}

@(private="file")
get_vulkan_layers :: proc() -> [dynamic]cstring {
	layers := make([dynamic]cstring)
	when ODIN_DEBUG { append(&layers, "VK_LAYER_KHRONOS_validation") }
	return layers
}

@(private="file")
get_vulkan_instance_extensions :: proc() -> [dynamic]cstring {
	extensions := make([dynamic]cstring)
	glfw_required_extensions := glfw.GetRequiredInstanceExtensions()
	append(&extensions, ..glfw_required_extensions[:])
	when ODIN_DEBUG { append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME) }
	return extensions
}

@(private="file")
get_vulkan_device_extensions :: proc() -> [dynamic]cstring {
	extensions := make([dynamic]cstring)
	append(&extensions, vk.KHR_SWAPCHAIN_EXTENSION_NAME)
	return extensions
}

@(private="file")
try_physical_device :: proc(physical_device: vk.PhysicalDevice,
			    required_device_extensions: []cstring,
			    window: glfw.WindowHandle,
			    surface: vk.SurfaceKHR) -> (swap_chain_properties: Swap_Chain_Properties, ok := false) {
	device_properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physical_device, &device_properties)
	if device_properties.deviceType != .DISCRETE_GPU do return

	device_extension_count: u32
	vk.EnumerateDeviceExtensionProperties(physical_device, nil, &device_extension_count, nil)
	device_extensions := make([dynamic]vk.ExtensionProperties, device_extension_count)
	defer delete(device_extensions)
	vk.EnumerateDeviceExtensionProperties(physical_device, nil, &device_extension_count, raw_data(device_extensions))

	for required_extension in required_device_extensions {
		required_extension_found := false

		for &device_extension in device_extensions {
			if required_extension == cast(cstring)raw_data(&device_extension.extensionName) {
				required_extension_found = true
				break
			}
		}

		if !required_extension_found do return
	}

	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &swap_chain_properties.surface_capabilities)

	surface_format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device,
					      surface,
					      &surface_format_count,
					      nil)
	surface_formats := make([dynamic]vk.SurfaceFormatKHR, surface_format_count)
	defer delete(surface_formats)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device,
					      surface,
					      &surface_format_count,
					      raw_data(surface_formats))

	presentation_mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device,
						   surface,
						   &presentation_mode_count,
						   nil)
	presentation_modes := make([dynamic]vk.PresentModeKHR, presentation_mode_count)
	defer delete(presentation_modes)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device,
						   surface,
						   &presentation_mode_count,
						   raw_data(presentation_modes))

	if len(surface_formats) == 0 || len(presentation_modes) == 0 do return

	swap_chain_properties.surface_format = surface_formats[0]
	for &format in surface_formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			swap_chain_properties.surface_format = format
			break
		}
	}

	swap_chain_properties.presentation_mode = .FIFO // FIFO is guaranteed to be available.
	for presentation_mode in presentation_modes {
		if presentation_mode == .MAILBOX {
			swap_chain_properties.presentation_mode = presentation_mode
			break
		}
	}

	swap_chain_properties.extent = swap_chain_properties.surface_capabilities.currentExtent
	if swap_chain_properties.surface_capabilities.currentExtent.width == max(u32) {
		// When the swap chain resolution can differ from the window's resolution, the values of currentExtent
		// are set to max(u32). We have to pick the resolution ourselves.
		width, height := glfw.GetFramebufferSize(window)
		swap_chain_properties.extent = vk.Extent2D { u32(width), u32(height) }
		swap_chain_properties.extent.width = clamp(swap_chain_properties.extent.width,
							   swap_chain_properties.surface_capabilities.minImageExtent.width,
							   swap_chain_properties.surface_capabilities.maxImageExtent.width)
		swap_chain_properties.extent.height = clamp(swap_chain_properties.extent.height,
							    swap_chain_properties.surface_capabilities.minImageExtent.height,
							    swap_chain_properties.surface_capabilities.maxImageExtent.height)
	}

	ok = true
	return
}

@(private="file")
destroy_image_views :: proc(device: vk.Device, image_views: []vk.ImageView) {
	for image_view in image_views do vk.DestroyImageView(device, image_view, nil)
}

@(private="file")
destroy_framebuffers :: proc(device: vk.Device, framebuffers: []vk.Framebuffer) {
	for framebuffer in framebuffers do vk.DestroyFramebuffer(device, framebuffer, nil)
}

@(private="file")
get_vk_debug_messenger_create_info :: proc() -> vk.DebugUtilsMessengerCreateInfoEXT {
	return vk.DebugUtilsMessengerCreateInfoEXT {
		sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = { .VERBOSE, /* .INFO, */ .WARNING, .ERROR },
		messageType = { .GENERAL, .VALIDATION, .PERFORMANCE },
		pfnUserCallback = vk_debug_utils_messenger_callback,
	}
}

@(private="file")
vk_debug_utils_messenger_callback :: proc "std" (message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
						 message_type: vk.DebugUtilsMessageTypeFlagsEXT,
						 callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
						 user_data: rawptr) -> b32 {
	context = g_context

	type_string: string
	switch message_type {
	case { .GENERAL }:
		type_string = "General"
	case { .VALIDATION }:
		type_string = "Validation"
	case { .PERFORMANCE }:
		type_string = "Performance"
	case:
		assert(false)
		type_string = "ERROR"
	}

	switch message_severity {
	case { .VERBOSE }:
		log.debugf("Vulkan %v: %v", type_string, callback_data.pMessage)
	case { .INFO }:
		log.infof("Vulkan %v: %v", type_string, callback_data.pMessage)
	case { .WARNING }:
		log.warnf("Vulkan %v: %v", type_string, callback_data.pMessage)
	case { .ERROR }:
		log.errorf("Vulkan %v: %v", type_string, callback_data.pMessage)
	}

	return b32(vk.FALSE)
}

@(private="file")
renderer_record_command_buffer :: proc(renderer: Renderer,
				       swap_chain_image_index: u32) -> (ok := false) {
	vk.ResetCommandBuffer(renderer.command_buffer, {})

	command_buffer_begin_info := vk.CommandBufferBeginInfo { sType = .COMMAND_BUFFER_BEGIN_INFO }
	if vk.BeginCommandBuffer(renderer.command_buffer, &command_buffer_begin_info) != .SUCCESS do return

	clear_color := vk.ClearValue { color = { float32 = { 0, 0, 0, 1 } } }
	render_pass_begin_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = renderer.render_pass,
		framebuffer = renderer.framebuffers[swap_chain_image_index],
		renderArea = {
			offset = { 0, 0 },
			extent = renderer.swap_chain_extent,
		},
		clearValueCount = 1,
		pClearValues = &clear_color,
	}

	vk.CmdBeginRenderPass(renderer.command_buffer, &render_pass_begin_info, .INLINE)
	vk.CmdBindPipeline(renderer.command_buffer, .GRAPHICS, renderer.pipeline)

	viewport := vk.Viewport {
		x = 0,
		y = 0,
		width = f32(renderer.swap_chain_extent.width),
		height = f32(renderer.swap_chain_extent.height),
		minDepth = 0,
		maxDepth = 1,
	}
	vk.CmdSetViewport(commandBuffer = renderer.command_buffer,
			  firstViewport = 0,
			  viewportCount = 1,
			  pViewports = &viewport)

	scissor := vk.Rect2D {
		offset = { 0, 0 },
		extent = renderer.swap_chain_extent,
	}
	vk.CmdSetScissor(commandBuffer = renderer.command_buffer,
			 firstScissor = 0,
			 scissorCount = 1,
			 pScissors = &scissor)

	vk.CmdDraw(commandBuffer = renderer.command_buffer,
		   vertexCount = 3,
		   instanceCount = 1,
		   firstVertex = 0,
		   firstInstance = 0)

	vk.CmdEndRenderPass(renderer.command_buffer)

	if vk.EndCommandBuffer(renderer.command_buffer) != .SUCCESS do return

	ok = true
	return
}

renderer_render :: proc(renderer: ^Renderer) -> (ok := false) {
	vk.WaitForFences(device = renderer.device,
			 fenceCount = 1,
			 pFences = &renderer.in_flight_fence,
			 waitAll = true,
			 timeout = max(u64))
	vk.ResetFences(renderer.device, 1, &renderer.in_flight_fence)

	swap_chain_image_index: u32
	vk.AcquireNextImageKHR(device = renderer.device,
			       swapchain = renderer.swap_chain,
			       timeout = max(u64),
			       semaphore = renderer.image_available_semaphore,
			       fence = vk.Fence(0),
			       pImageIndex = &swap_chain_image_index)

	renderer_record_command_buffer(renderer^, swap_chain_image_index)

	pipeline_waiting_stages := vk.PipelineStageFlags{ .COLOR_ATTACHMENT_OUTPUT }
	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		waitSemaphoreCount = 1,
		pWaitSemaphores = &renderer.image_available_semaphore,
		pWaitDstStageMask = &pipeline_waiting_stages,
		commandBufferCount = 1,
		pCommandBuffers = &renderer.command_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores = &renderer.render_finished_semaphore,
	}
	if vk.QueueSubmit(renderer.graphics_queue, 1, &submit_info, renderer.in_flight_fence) != .SUCCESS {
		log.errorf("Failed to submit draw command buffer to the graphics queue.")
		return
	}

	presentation_info := vk.PresentInfoKHR {
		sType = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores = &renderer.render_finished_semaphore,
		swapchainCount = 1,
		pSwapchains = &renderer.swap_chain,
		pImageIndices = &swap_chain_image_index,
	}

	vk.QueuePresentKHR(renderer.presentation_queue, &presentation_info)

	ok = true
	return
}
