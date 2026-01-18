package vulkan_renderer

import vk "vendor:vulkan"
import "vendor:glfw"

import "core:log"

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
}

init_renderer :: proc(renderer: ^Renderer,
		      application_name: cstring,
		      glfw_window_handle: glfw.WindowHandle) -> (ok := false) {
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
	assert(vk.CreateInstance != nil, "Vulkan function pointers not loaded")

	application_info := vk.ApplicationInfo {
		sType = .APPLICATION_INFO,
		pApplicationName = application_name,
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName = "No Engine",
		engineVersion = vk.MAKE_VERSION(1, 0, 0),
		apiVersion = vk.API_VERSION_1_0,
	}

	wanted_layers := get_vulkan_layers()
	defer delete(wanted_layers)
	wanted_instance_extensions := get_vulkan_instance_extensions()
	defer delete(wanted_instance_extensions)
	wanted_device_extensions := get_vulkan_device_extensions()
	defer delete(wanted_device_extensions)

	instance_debug_messenger_create_info := get_vk_debug_messenger_create_info()
	instance_create_info := vk.InstanceCreateInfo {
		sType = .INSTANCE_CREATE_INFO,
		pNext = &instance_debug_messenger_create_info,
		pApplicationInfo = &application_info,
		enabledLayerCount = cast(u32)len(wanted_layers),
		ppEnabledLayerNames = raw_data(wanted_layers),
		enabledExtensionCount = cast(u32)len(wanted_instance_extensions),
		ppEnabledExtensionNames = raw_data(wanted_instance_extensions),
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

	if glfw.CreateWindowSurface(renderer.instance, glfw_window_handle, nil, &renderer.surface) != .SUCCESS do return
	defer if !ok do vk.DestroySurfaceKHR(renderer.instance, renderer.surface, nil)

	physical_device_count: u32
	vk.EnumeratePhysicalDevices(renderer.instance, &physical_device_count, nil)
	if physical_device_count == 0 do return
	physical_devices := make([dynamic]vk.PhysicalDevice, physical_device_count)
	defer delete(physical_devices)
	vk.EnumeratePhysicalDevices(renderer.instance, &physical_device_count, raw_data(physical_devices))

	suitable_physical_device_found := false
	for &device in physical_devices {
		if is_suitable_physical_device(device, wanted_device_extensions[:]) {
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
		enabledLayerCount = cast(u32)len(wanted_layers),
		ppEnabledLayerNames = raw_data(wanted_layers),
		enabledExtensionCount = cast(u32)len(wanted_device_extensions),
		ppEnabledExtensionNames = raw_data(wanted_device_extensions),
	}

	if vk.CreateDevice(renderer.physical_device, &device_create_info, nil, &renderer.device) != .SUCCESS do return
	defer if !ok do vk.DestroyDevice(renderer.device, nil)
	vk.GetDeviceQueue(renderer.device, renderer.graphics_queue_family_index, 0, &renderer.graphics_queue)
	vk.GetDeviceQueue(renderer.device, renderer.presentation_queue_family_index, 0, &renderer.presentation_queue)

	ok = true
	return
}

deinit_renderer :: proc(renderer: ^Renderer) {
	vk.DestroyDevice(renderer.device, nil)
	vk.DestroySurfaceKHR(renderer.instance, renderer.surface, nil)
	when ODIN_DEBUG { vk.DestroyDebugUtilsMessengerEXT(renderer.instance, renderer.debug_utils_messenger, nil) }
	vk.DestroyInstance(renderer.instance, nil)
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
is_suitable_physical_device :: proc(physical_device: vk.PhysicalDevice,
				    required_device_extensions: []cstring) -> (ok := false) {
	device_properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physical_device, &device_properties)
	device_features: vk.PhysicalDeviceFeatures
	vk.GetPhysicalDeviceFeatures(physical_device, &device_features)

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

	if device_properties.deviceType != .DISCRETE_GPU do return

	ok = true
	return
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
