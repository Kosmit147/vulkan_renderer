package vulkan_renderer

import vk "vendor:vulkan"
import "vendor:glfw"

import "core:log"

Renderer :: struct {
	instance: vk.Instance,
}

init_renderer :: proc(renderer: ^Renderer, application_name: cstring) -> (ok := false) {
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
	wanted_extensions := get_vulkan_extensions()
	defer delete(wanted_extensions)

	instance_create_info := vk.InstanceCreateInfo {
		sType = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &application_info,
		enabledLayerCount = cast(u32)len(wanted_layers),
		ppEnabledLayerNames = raw_data(wanted_layers),
		enabledExtensionCount = cast(u32)len(wanted_extensions),
		ppEnabledExtensionNames = raw_data(wanted_extensions),
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

	ok = true
	return
}

deinit_renderer :: proc(renderer: ^Renderer) {
	vk.DestroyInstance(renderer.instance, nil)
}

@(private="file")
get_vulkan_layers :: proc() -> [dynamic]cstring {
	layers := make([dynamic]cstring)
	when ODIN_DEBUG { append(&layers, "VK_LAYER_KHRONOS_validation") }
	return layers
}

@(private="file")
get_vulkan_extensions :: proc() -> [dynamic]cstring {
	extensions := make([dynamic]cstring)
	glfw_required_extensions := glfw.GetRequiredInstanceExtensions()
	append(&extensions, ..glfw_required_extensions[:])
	return extensions
}
