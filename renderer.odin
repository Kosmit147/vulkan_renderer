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

	pipeline_layout: vk.PipelineLayout,
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
	init_renderer_graphics_pipeline(renderer) or_return
	defer if !ok do deinit_renderer_graphics_pipeline(renderer^)

	ok = true
	return
}

deinit_renderer :: proc(renderer: Renderer) {
	deinit_renderer_graphics_pipeline(renderer)
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

	dynamic_states := [2]vk.DynamicState { .VIEWPORT, .SCISSOR }
	pipeline_dynamic_state_create_info := vk.PipelineDynamicStateCreateInfo {
		sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = cast(u32)len(dynamic_states),
		pDynamicStates = raw_data(&dynamic_states),
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

	pipeline_layout_create_info := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
	}

	if vk.CreatePipelineLayout(renderer.device, &pipeline_layout_create_info, nil, &renderer.pipeline_layout) != .SUCCESS {
		return
	}

	ok = true
	return
}

@(private="file")
deinit_renderer_graphics_pipeline :: proc(renderer: Renderer) {
	vk.DestroyPipelineLayout(renderer.device, renderer.pipeline_layout, nil)
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
