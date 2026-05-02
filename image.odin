package vulkan_renderer

import vk "vendor:vulkan"

create_image :: proc(device: vk.Device,
		     physical_device: vk.PhysicalDevice,
		     width, height: u32,
		     mip_levels: u32,
		     format: vk.Format,
		     tiling: vk.ImageTiling,
		     samples: vk.SampleCountFlag,
		     usage: vk.ImageUsageFlags,
		     memory_properties: vk.MemoryPropertyFlags) -> (image: vk.Image,
								    image_memory: vk.DeviceMemory,
								    ok := false) {
	image_create_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = {
			width = width,
			height = height,
			depth = 1,
		},
		mipLevels = mip_levels,
		arrayLayers = 1,
		format = format,
		tiling = tiling,
		initialLayout = .UNDEFINED,
		usage = usage,
		sharingMode = .EXCLUSIVE,
		samples = { samples },
	}

	if vk.CreateImage(device, &image_create_info, nil, &image) != .SUCCESS do return
	defer if !ok do vk.DestroyImage(device, image, nil)

	memory_requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(device, image, &memory_requirements)
	memory_type_index := find_memory_type(physical_device,
					      memory_requirements.memoryTypeBits,
					      memory_properties) or_return

	memory_alloc_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = memory_requirements.size,
		memoryTypeIndex = memory_type_index,
	}

	if vk.AllocateMemory(device, &memory_alloc_info, nil, &image_memory) != .SUCCESS do return
	defer if !ok do vk.FreeMemory(device, image_memory, nil)

	vk.BindImageMemory(device, image, image_memory, 0)

	ok = true
	return
}

destroy_image :: proc(device: vk.Device, image: vk.Image, image_memory: vk.DeviceMemory) {
	vk.DestroyImage(device, image, nil)
	vk.FreeMemory(device, image_memory, nil)
}

transition_image_layout :: proc(device: vk.Device,
				command_pool: vk.CommandPool,
				queue: vk.Queue,
				image: vk.Image,
				format: vk.Format,
				mip_levels: u32,
				old_layout: vk.ImageLayout,
				new_layout: vk.ImageLayout) {
	command_buffer := begin_single_time_commands(device, command_pool)

	src_access_mask, dst_access_mask: vk.AccessFlags
	src_stage_mask, dst_stage_mask: vk.PipelineStageFlags

	if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL {
		src_access_mask = {}
		dst_access_mask = { .TRANSFER_WRITE }
		src_stage_mask = { .TOP_OF_PIPE }
		dst_stage_mask = { .TRANSFER }
	} else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		src_access_mask = { .TRANSFER_WRITE }
		dst_access_mask = { .SHADER_READ }
		src_stage_mask = { .TRANSFER }
		dst_stage_mask = { .FRAGMENT_SHADER }
	} else {
		assert(false, "unsupported layout transition")
	}

	image_memory_barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {
			aspectMask = { .COLOR },
			baseMipLevel = 0,
			levelCount = mip_levels,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		srcAccessMask = src_access_mask,
		dstAccessMask = dst_access_mask,
	}

	vk.CmdPipelineBarrier(commandBuffer = command_buffer,
			      srcStageMask = src_stage_mask,
			      dstStageMask = dst_stage_mask,
			      dependencyFlags = {},
			      memoryBarrierCount = 0,
			      pMemoryBarriers = nil,
			      bufferMemoryBarrierCount = 0,
			      pBufferMemoryBarriers = nil,
			      imageMemoryBarrierCount = 1,
			      pImageMemoryBarriers = &image_memory_barrier)

	submit_single_time_commands(command_buffer, queue, device, command_pool)
}

copy_buffer_to_image :: proc(device: vk.Device,
			     command_pool: vk.CommandPool,
			     queue: vk.Queue,
			     buffer: vk.Buffer,
			     image: vk.Image,
			     width, height: u32) {
	command_buffer := begin_single_time_commands(device, command_pool)

	copy_region := vk.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = {
			aspectMask = { .COLOR },
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		imageOffset = { 0, 0, 0 },
		imageExtent = {
			width = width,
			height = height,
			depth = 1,
		}
	}
	vk.CmdCopyBufferToImage(commandBuffer = command_buffer,
				srcBuffer = buffer,
				dstImage = image,
				dstImageLayout = .TRANSFER_DST_OPTIMAL,
				regionCount = 1,
				pRegions = &copy_region)

	submit_single_time_commands(command_buffer, queue, device, command_pool)
}

create_image_view :: proc(device: vk.Device,
			  image: vk.Image,
			  format: vk.Format,
			  mip_levels: u32,
			  aspect: vk.ImageAspectFlags) -> (view: vk.ImageView, ok := false) {
	image_view_create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image,
		viewType = .D2,
		format = format,
		components = { .IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY },
		subresourceRange = {
			aspectMask = aspect,
			baseMipLevel = 0,
			levelCount = mip_levels,
			baseArrayLayer = 0,
			layerCount = 1,
		}
	}

	if vk.CreateImageView(device, &image_view_create_info, nil, &view) !=. SUCCESS do return

	ok = true
	return
}

destroy_image_view :: proc(device: vk.Device, view: vk.ImageView) {
	vk.DestroyImageView(device, view, nil)
}

find_supported_format :: proc(physical_device: vk.PhysicalDevice,
			      candidates: []vk.Format,
			      tiling: vk.ImageTiling,
			      features: vk.FormatFeatureFlags) -> (vk.Format, bool) {
	for format in candidates {
		format_properties: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(physical_device, format, &format_properties)
		if tiling == .LINEAR && (features <= format_properties.linearTilingFeatures) do return format, true
		if tiling == .OPTIMAL && (features <= format_properties.optimalTilingFeatures) do return format, true
	}

	return {}, false
}

generate_mipmaps :: proc(device: vk.Device,
			 physical_device: vk.PhysicalDevice,
			 command_pool: vk.CommandPool,
			 queue: vk.Queue,
			 image: vk.Image,
			 image_format: vk.Format,
			 width, height: u32,
			 mip_levels: u32) -> (ok := false) {
	format_properties: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(physical_device, image_format, &format_properties)
	if .SAMPLED_IMAGE_FILTER_LINEAR not_in format_properties.optimalTilingFeatures do return

	command_buffer := begin_single_time_commands(device, command_pool)

	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		image = image,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		subresourceRange = {
			aspectMask = { .COLOR },
			baseArrayLayer = 0,
			layerCount = 1,
			levelCount = 1,
		}
	}

	mip_width, mip_height := width, height

	for i := u32(1); i < mip_levels; i += 1 {
		barrier.subresourceRange.baseMipLevel = i - 1
		barrier.oldLayout = .TRANSFER_DST_OPTIMAL
		barrier.newLayout = .TRANSFER_SRC_OPTIMAL
		barrier.srcAccessMask = { .TRANSFER_WRITE }
		barrier.dstAccessMask = { .TRANSFER_READ }

		vk.CmdPipelineBarrier(commandBuffer = command_buffer,
				      srcStageMask = { .TRANSFER },
				      dstStageMask = { .TRANSFER },
				      dependencyFlags = {},
				      memoryBarrierCount = 0,
				      pMemoryBarriers = nil,
				      bufferMemoryBarrierCount = 0,
				      pBufferMemoryBarriers = nil,
				      imageMemoryBarrierCount = 1,
				      pImageMemoryBarriers = &barrier)

		image_blit := vk.ImageBlit {
			srcOffsets = {
				{ 0, 0, 0 },
				{ i32(mip_width), i32(mip_height), 1 },
			},
			srcSubresource = {
				aspectMask = { .COLOR },
				mipLevel = i - 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
			dstOffsets = {
				{ 0, 0, 0 },
				{ i32(mip_width) / 2 if mip_width > 1 else 1, i32(mip_height) / 2 if mip_height > 1 else 1, 1 }
			},
			dstSubresource = {
				aspectMask = { .COLOR },
				mipLevel = i,
				baseArrayLayer = 0,
				layerCount = 1,
			}
		}

		vk.CmdBlitImage(commandBuffer = command_buffer,
				srcImage = image,
				srcImageLayout = .TRANSFER_SRC_OPTIMAL,
				dstImage = image,
				dstImageLayout = .TRANSFER_DST_OPTIMAL,
				regionCount = 1,
				pRegions = &image_blit,
				filter = .LINEAR)

		barrier.oldLayout = .TRANSFER_SRC_OPTIMAL
		barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
		barrier.srcAccessMask = { .TRANSFER_READ }
		barrier.dstAccessMask = { .SHADER_READ }

		vk.CmdPipelineBarrier(commandBuffer = command_buffer,
				      srcStageMask = { .TRANSFER },
				      dstStageMask = { .FRAGMENT_SHADER },
				      dependencyFlags = {},
				      memoryBarrierCount = 0,
				      pMemoryBarriers = nil,
				      bufferMemoryBarrierCount = 0,
				      pBufferMemoryBarriers = nil,
				      imageMemoryBarrierCount = 1,
				      pImageMemoryBarriers = &barrier)

		if mip_width > 1 do mip_width /= 2
		if mip_height > 1 do mip_height /= 2
	}

	barrier.subresourceRange.baseMipLevel = mip_levels - 1
	barrier.oldLayout = .TRANSFER_DST_OPTIMAL
	barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
	barrier.srcAccessMask = { .TRANSFER_WRITE }
	barrier.dstAccessMask = { .SHADER_READ }

	vk.CmdPipelineBarrier(commandBuffer = command_buffer,
			      srcStageMask = { .TRANSFER },
			      dstStageMask = { .FRAGMENT_SHADER },
			      dependencyFlags = {},
			      memoryBarrierCount = 0,
			      pMemoryBarriers = nil,
			      bufferMemoryBarrierCount = 0,
			      pBufferMemoryBarriers = nil,
			      imageMemoryBarrierCount = 1,
			      pImageMemoryBarriers = &barrier)

	submit_single_time_commands(command_buffer, queue, device, command_pool)

	ok = true
	return
}
