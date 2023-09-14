static import std.file;

import std.stdio : writeln, StdioException;
import std.exception : enforce;
import std.container.rbtree;
import std.range;
import std.algorithm.iteration;
import std.string;
import core.stdc.stdio : fprintf, stderr;
import core.stdc.string : strcmp;

import erupted;
import erupted.dispatch_device;
import erupted.vulkan_lib_loader;

import bindbc.glfw;
import loader = bindbc.loader.sharedlib;
import optional;
import utils;
import std.logger.core;

mixin(bindGLFW_Vulkan);

private static const uint WIDTH = 800;
private static const uint HEIGHT = 600;

private static const(const char*)[] validationLayers = [
  "VK_LAYER_KHRONOS_validation"
];

private static const(const char*)[] deviceExtensions = [
  VK_KHR_SWAPCHAIN_EXTENSION_NAME
];

private void assertVk(VkResult result)
{
  enforce(result == VK_SUCCESS, "Failed to perform vulkan operation.");
}

extern (Windows) static VkBool32 debugCallback(VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
  VkDebugUtilsMessageTypeFlagsEXT messageType,
  const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData, void* pUserData) nothrow @nogc
{
  final switch (messageSeverity)
  {
  case VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT:
    fprintf(stderr, "VERBOSE: ");
    break;
  case VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT:
    fprintf(stderr, "INFO: ");
    break;
  case VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT:
    fprintf(stderr, "WARNING: ");
    break;
  case VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT:
    fprintf(stderr, "ERROR: ");
    break;
  case VK_DEBUG_UTILS_MESSAGE_SEVERITY_FLAG_BITS_MAX_ENUM_EXT:
    fprintf(stderr, "MAX INFO: ");
    break;
  }

  fprintf(stderr, "%s\n", pCallbackData.pMessage);
  return VK_FALSE;
}

VkResult createDebugUtilsMessengerEXT(VkInstance instance, const VkDebugUtilsMessengerCreateInfoEXT* pCreateInfo,
  const VkAllocationCallbacks* pAllocator, VkDebugUtilsMessengerEXT* pDebugMessenger)
{
  auto func = cast(PFN_vkCreateDebugUtilsMessengerEXT) vkGetInstanceProcAddr(instance,
    "vkCreateDebugUtilsMessengerEXT");

  if (func != null)
  {
    return func(instance, pCreateInfo, pAllocator, pDebugMessenger);
  }
  else
  {
    return VK_ERROR_EXTENSION_NOT_PRESENT;
  }
}

void destroyDebugUtilsMessengerEXT(VkInstance instance,
  VkDebugUtilsMessengerEXT debugMessenger, const VkAllocationCallbacks* pAllocator)
{
  auto func = cast(PFN_vkDestroyDebugUtilsMessengerEXT) vkGetInstanceProcAddr(instance,
    "vkDestroyDebugUtilsMessengerEXT");

  if (func != null)
  {
    func(instance, debugMessenger, pAllocator);
  }
}

// Structs used by HelloTriangleApp

struct QueueFamilyIndices
{
  Optional!uint graphicsFamily;
  Optional!uint presentFamily;

  bool isComplete()
  {
    return !graphicsFamily.empty && !presentFamily.empty;
  }
}

struct SwapchainSupportDetails
{
  VkSurfaceCapabilitiesKHR capabilities;
  VkSurfaceFormatKHR[] formats;
  VkPresentModeKHR[] presentModes;
}

final class HelloTriangleApp
{
  void run()
  {
    initWindow();
    initVulkan();
    mainLoop();
    cleanup();
  }

private:
  GLFWwindow* mWindow;
  VkInstance mInstance;
  VkDebugUtilsMessengerEXT mDebugMessenger;
  VkPhysicalDevice mPhysicalDevice = VK_NULL_HANDLE;
  DispatchDevice mDevice;
  VkQueue mGraphicsQueue;
  VkQueue mPresentQueue;
  VkSurfaceKHR mSurface;

  VkSwapchainKHR mSwapchain;
  VkImage[] mSwapchainImages;
  VkFormat mSwapchainImageFormat;
  VkExtent2D mSwapchainExtent;
  VkImageView[] mSwapchainImageViews;
  VkFramebuffer[] mSwapchainFramebuffers;

  VkRenderPass mRenderPass;
  VkPipelineLayout mPipelineLayout;
  VkPipeline mGraphicsPipeline;

  VkCommandPool mCommandPool;
  VkCommandBuffer mCommandBuffer;

  VkSemaphore mImageAvailableSemaphore;
  VkSemaphore mRenderFinishedSemaphore;
  VkFence mInFlightFence;

  bool loadGLFWLib()
  {
    auto ret = loadGLFW();
    loadGLFW_Vulkan();

    if (ret != glfwSupport)
    {
      // Log the error info
      foreach (info; loader.errors)
      {
        writeln("Error loading GLFW: ", info.error);
      }

      string msg;
      if (ret == GLFWSupport.noLibrary)
      {
        msg = "This application requires the GLFW library.";
      }
      else
      {
        msg = "The version of the GLFW library on your system is too low. Please upgrade.";
      }

      writeln(msg);
      return false;
    }

    return true;
  }

  void initWindow()
  {
    enforce(loadGLFWLib(), "Failed to load GLFW shared library.");
    glfwInit();

    auto res = glfwVulkanSupported();
    enforce(res != GLFW_FALSE, "Vulkan is not supported by GLFW");

    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);

    mWindow = glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", null, null);
  }

  void initVulkan()
  {
    import erupted.vulkan_lib_loader;

    if (!loadGlobalLevelFunctions())
    {
      throw new Exception("Failed to load global Vulkan Functions!");
    }

    createInstance();
    debug setupDebugMessenger();
    createSurface();
    pickPhysicalDevice();
    createLogicalDevice();
    createSwapchain();
    createImageViews();
    createRenderPass();
    createGraphicsPipeline();
    createFramebuffers();
    createCommandPool();
    createCommandBuffer();
    createSyncObjects();
  }

  void mainLoop()
  {
    while (!glfwWindowShouldClose(mWindow))
    {
      glfwPollEvents();
      drawFrame();
    }

    mDevice.DeviceWaitIdle();
  }

  void cleanup()
  {
    mDevice.DestroySemaphore(mRenderFinishedSemaphore);
    mDevice.DestroySemaphore(mImageAvailableSemaphore);
    mDevice.DestroyFence(mInFlightFence);

    mDevice.DestroyCommandPool(mCommandPool);

    foreach (framebuffer; mSwapchainFramebuffers)
    {
      mDevice.DestroyFramebuffer(framebuffer);
    }

    mDevice.DestroyPipeline(mGraphicsPipeline);
    mDevice.DestroyPipelineLayout(mPipelineLayout);
    mDevice.DestroyRenderPass(mRenderPass);

    foreach (imageView; mSwapchainImageViews)
    {
      mDevice.DestroyImageView(imageView);
    }

    mDevice.DestroySwapchainKHR(mSwapchain);
    mDevice.DestroyDevice();

    debug destroyDebugUtilsMessengerEXT(mInstance, mDebugMessenger, null);

    vkDestroySurfaceKHR(mInstance, mSurface, null);
    vkDestroyInstance(mInstance, null);

    assert(freeVulkanLib());

    glfwDestroyWindow(mWindow);
    glfwTerminate();
  }

  void createInstance()
  {
    debug assert(checkValidationLayerSupport(), "Validation layers requested, but not available!");

    VkApplicationInfo appInfo;
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Hello Triangle";
    appInfo.applicationVersion = VK_API_VERSION_1_0;
    appInfo.pEngineName = "No Engine";
    appInfo.engineVersion = VK_API_VERSION_1_0;
    appInfo.apiVersion = VK_API_VERSION_1_0;

    VkInstanceCreateInfo createInfo;
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;

    // Enable the correct extensions
    auto requiredExtensions = getRequiredExtensions();

    createInfo.enabledExtensionCount = cast(uint32_t) requiredExtensions.length;
    createInfo.ppEnabledExtensionNames = requiredExtensions.ptr;

    debug
    {
      VkDebugUtilsMessengerCreateInfoEXT debugCreateInfo;
      populateDebugMessengerCreateInfo(debugCreateInfo);
      createInfo.pNext = cast(VkDebugUtilsMessengerCreateInfoEXT*)&debugCreateInfo;

      createInfo.enabledLayerCount = cast(uint) validationLayers.length;
      createInfo.ppEnabledLayerNames = validationLayers.ptr;
    }
    else
    {
      createInfo.enabledLayerCount = 0;
      createInfo.pNext = null;
    }

    if (vkCreateInstance(&createInfo, null, &mInstance) != VK_SUCCESS)
    {
      writeln("Failed to create Vulkan instance.");
    }

    // Load the instance level functions
    loadInstanceLevelFunctions(mInstance);

    // Show the available extensions in debug mode and setup debug messenger
    debug
    {
      uint32_t extension_count = 0;
      vkEnumerateInstanceExtensionProperties(null, &extension_count, null);

      auto extensions = new VkExtensionProperties[extension_count];
      vkEnumerateInstanceExtensionProperties(null, &extension_count, extensions.ptr);

      writeln("Extensions: ");
      foreach (extension; extensions)
      {
        writeln("\t", extension.extensionName);
      }
    }
  }

  void createSurface()
  {
    assertVk(glfwCreateWindowSurface(mInstance, mWindow, null, &mSurface));
  }

  void pickPhysicalDevice()
  {
    uint32_t device_count = 0;
    vkEnumeratePhysicalDevices(mInstance, &device_count, null);

    enforce(device_count > 0, "Failed to find GPUs with Vulkan support!");

    auto devices = new VkPhysicalDevice[device_count];
    vkEnumeratePhysicalDevices(mInstance, &device_count, devices.ptr);

    foreach (ref device; devices)
    {
      if (isDeviceSuitable(device))
      {
        mPhysicalDevice = device;
        break;
      }
    }

    enforce(mPhysicalDevice != VK_NULL_HANDLE, "Failed to find a suitable GPU!");
  }

  void createLogicalDevice()
  {
    QueueFamilyIndices indices = findQueueFamilies(mPhysicalDevice);

    VkDeviceQueueCreateInfo[] queueCreateInfos;
    RedBlackTree!uint32_t uniqueQueueFamilies = redBlackTree([
      indices.graphicsFamily.front, indices.presentFamily.front
    ]);

    // Set queue priority
    float queuePriority = 1.0f;

    foreach (uint32_t queueFamily; uniqueQueueFamilies)
    {
      VkDeviceQueueCreateInfo queueCreateInfo;
      queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
      queueCreateInfo.queueFamilyIndex = queueFamily;
      queueCreateInfo.queueCount = 1;
      queueCreateInfo.pQueuePriorities = &queuePriority;
      queueCreateInfos ~= queueCreateInfo;
    }

    VkPhysicalDeviceFeatures deviceFeatures;

    VkDeviceCreateInfo createInfo;
    createInfo.queueCreateInfoCount = cast(uint) queueCreateInfos.length;
    createInfo.pQueueCreateInfos = queueCreateInfos.ptr;
    createInfo.pEnabledFeatures = &deviceFeatures;
    createInfo.enabledExtensionCount = cast(uint) deviceExtensions.length;
    createInfo.ppEnabledExtensionNames = deviceExtensions.ptr;

    debug
    {
      createInfo.enabledLayerCount = cast(uint) validationLayers.length;
      createInfo.ppEnabledLayerNames = validationLayers.ptr;
    }
    else
    {
      createInfo.enabledLayerCount = 0;
    }

    VkDevice device;
    assertVk(vkCreateDevice(mPhysicalDevice, &createInfo, null, &device));
    loadDeviceLevelFunctions(device);

    mDevice = DispatchDevice(device);
    mDevice.GetDeviceQueue(indices.graphicsFamily.front, 0, &mGraphicsQueue);
    mDevice.GetDeviceQueue(indices.presentFamily.front, 0, &mPresentQueue);
  }

  void createSwapchain()
  {
    SwapchainSupportDetails swapchainSupport = querySwapchainSupport(mPhysicalDevice);

    VkSurfaceFormatKHR surfaceFormat = chooseSwapSurfaceFormat(swapchainSupport.formats);
    VkPresentModeKHR presentMode = chooseSwapPresentMode(swapchainSupport.presentModes);
    VkExtent2D extent = chooseSwapExtent(swapchainSupport.capabilities);

    uint32_t imageCount = swapchainSupport.capabilities.minImageCount + 1;
    if (swapchainSupport.capabilities.maxImageCount > 0
      && imageCount > swapchainSupport.capabilities.maxImageCount)
    {
      imageCount = swapchainSupport.capabilities.maxImageCount;
    }

    VkSwapchainCreateInfoKHR createInfo;
    createInfo.surface = mSurface;
    createInfo.minImageCount = imageCount;
    createInfo.imageFormat = surfaceFormat.format;
    createInfo.imageColorSpace = surfaceFormat.colorSpace;
    createInfo.imageExtent = extent;
    createInfo.imageArrayLayers = 1;
    createInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

    QueueFamilyIndices indices = findQueueFamilies(mPhysicalDevice);
    uint32_t[] queueFamilyIndices = [
      indices.graphicsFamily.front, indices.presentFamily.front
    ];

    if (indices.graphicsFamily != indices.presentFamily)
    {
      createInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
      createInfo.queueFamilyIndexCount = 2;
      createInfo.pQueueFamilyIndices = queueFamilyIndices.ptr;
    }
    else
    {
      createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    }

    createInfo.preTransform = swapchainSupport.capabilities.currentTransform;
    createInfo.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    createInfo.presentMode = presentMode;
    createInfo.clipped = VK_TRUE;

    createInfo.oldSwapchain = VK_NULL_HANDLE;

    assertVk(mDevice.CreateSwapchainKHR(&createInfo, &mSwapchain));

    mDevice.GetSwapchainImagesKHR(mSwapchain, &imageCount, null);
    mSwapchainImages.length = imageCount;
    mDevice.GetSwapchainImagesKHR(mSwapchain, &imageCount, mSwapchainImages.ptr);

    mSwapchainImageFormat = surfaceFormat.format;
    mSwapchainExtent = extent;
  }

  void createImageViews()
  {
    mSwapchainImageViews.length = mSwapchainImages.length;

    foreach (i; 0 .. mSwapchainImages.length)
    {
      VkImageViewCreateInfo createInfo;
      createInfo.image = mSwapchainImages[i];
      createInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
      createInfo.format = mSwapchainImageFormat;
      createInfo.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
      createInfo.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
      createInfo.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
      createInfo.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
      createInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
      createInfo.subresourceRange.baseMipLevel = 0;
      createInfo.subresourceRange.levelCount = 1;
      createInfo.subresourceRange.baseArrayLayer = 0;
      createInfo.subresourceRange.layerCount = 1;

      assertVk(mDevice.CreateImageView(&createInfo, &mSwapchainImageViews[i]));
    }
  }

  void createRenderPass()
  {
    VkAttachmentDescription colorAttachment;
    colorAttachment.format = mSwapchainImageFormat;
    colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
    colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

    VkAttachmentReference colorAttachmentRef;
    colorAttachmentRef.attachment = 0;
    colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkSubpassDescription subpass;
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &colorAttachmentRef;

    VkSubpassDependency dependency;
    dependency.srcSubpass = VK_SUBPASS_EXTERNAL;
    dependency.dstSubpass = 0;
    dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.srcAccessMask = 0;
    dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

    VkRenderPassCreateInfo renderPassInfo;
    renderPassInfo.attachmentCount = 1;
    renderPassInfo.pAttachments = &colorAttachment;
    renderPassInfo.subpassCount = 1;
    renderPassInfo.pSubpasses = &subpass;
    renderPassInfo.dependencyCount = 1;
    renderPassInfo.pDependencies = &dependency;

    assertVk(mDevice.CreateRenderPass(&renderPassInfo, &mRenderPass));
  }

  void createGraphicsPipeline()
  {
    const char[] vertShaderCode = cast(char[]) std.file.read("shaders/vert.spv");
    const char[] fragShaderCode = cast(char[]) std.file.read("shaders/frag.spv");

    VkShaderModule vertShaderModule = createShaderModule(vertShaderCode);
    VkShaderModule fragShaderModule = createShaderModule(fragShaderCode);

    scope (exit)
    {
      mDevice.DestroyShaderModule(fragShaderModule);
      mDevice.DestroyShaderModule(vertShaderModule);
    }

    VkPipelineShaderStageCreateInfo vertShaderStageInfo;
    vertShaderStageInfo.stage = VK_SHADER_STAGE_VERTEX_BIT;
    vertShaderStageInfo.Module = vertShaderModule;
    vertShaderStageInfo.pName = "main";

    VkPipelineShaderStageCreateInfo fragShaderStageInfo;
    fragShaderStageInfo.stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    fragShaderStageInfo.Module = fragShaderModule;
    fragShaderStageInfo.pName = "main";

    VkPipelineShaderStageCreateInfo[] shaderStages = [
      vertShaderStageInfo, fragShaderStageInfo
    ];

    VkPipelineVertexInputStateCreateInfo vertexInputInfo;
    vertexInputInfo.vertexBindingDescriptionCount = 0;
    vertexInputInfo.vertexAttributeDescriptionCount = 0;

    VkPipelineInputAssemblyStateCreateInfo inputAssembly;
    inputAssembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    inputAssembly.primitiveRestartEnable = VK_FALSE;

    VkPipelineViewportStateCreateInfo viewportState;
    viewportState.viewportCount = 1;
    viewportState.scissorCount = 1;

    VkPipelineRasterizationStateCreateInfo rasterizer;
    rasterizer.depthClampEnable = VK_FALSE;
    rasterizer.rasterizerDiscardEnable = VK_FALSE;
    rasterizer.polygonMode = VK_POLYGON_MODE_FILL;
    rasterizer.lineWidth = 1.0f;
    rasterizer.cullMode = VK_CULL_MODE_BACK_BIT;
    rasterizer.frontFace = VK_FRONT_FACE_CLOCKWISE;
    rasterizer.depthBiasEnable = VK_FALSE;
    rasterizer.depthBiasClamp = 0.0f;

    VkPipelineMultisampleStateCreateInfo multisampling;
    multisampling.sampleShadingEnable = VK_FALSE;
    multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

    VkPipelineColorBlendAttachmentState colorBlendAttachment;
    colorBlendAttachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT
      | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    colorBlendAttachment.blendEnable = VK_FALSE;

    VkPipelineColorBlendStateCreateInfo colorBlending;
    colorBlending.logicOpEnable = VK_FALSE;
    colorBlending.logicOp = VK_LOGIC_OP_COPY;
    colorBlending.attachmentCount = 1;
    colorBlending.pAttachments = &colorBlendAttachment;
    colorBlending.blendConstants = [0.0f, 0.0f, 0.0f, 0.0f];

    VkDynamicState[] dynamicStates = [
      VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR
    ];
    VkPipelineDynamicStateCreateInfo dynamicState;
    dynamicState.dynamicStateCount = cast(uint32_t) dynamicStates.length;
    dynamicState.pDynamicStates = dynamicStates.ptr;

    VkPipelineLayoutCreateInfo pipelineLayoutInfo;
    pipelineLayoutInfo.setLayoutCount = 0;
    pipelineLayoutInfo.pushConstantRangeCount = 0;

    assertVk(mDevice.CreatePipelineLayout(&pipelineLayoutInfo, &mPipelineLayout));

    VkGraphicsPipelineCreateInfo pipelineInfo;
    pipelineInfo.stageCount = 2;
    pipelineInfo.pStages = shaderStages.ptr;
    pipelineInfo.pVertexInputState = &vertexInputInfo;
    pipelineInfo.pInputAssemblyState = &inputAssembly;
    pipelineInfo.pViewportState = &viewportState;
    pipelineInfo.pRasterizationState = &rasterizer;
    pipelineInfo.pMultisampleState = &multisampling;
    pipelineInfo.pColorBlendState = &colorBlending;
    pipelineInfo.pDynamicState = &dynamicState;
    pipelineInfo.layout = mPipelineLayout;
    pipelineInfo.renderPass = mRenderPass;
    pipelineInfo.subpass = 0;
    pipelineInfo.basePipelineHandle = VK_NULL_HANDLE;

    assertVk(mDevice.CreateGraphicsPipelines(VK_NULL_HANDLE, 1, &pipelineInfo,
        &mGraphicsPipeline));
  }

  void createFramebuffers()
  {
    mSwapchainFramebuffers.length = mSwapchainImageViews.length;

    foreach (i; 0 .. mSwapchainImageViews.length)
    {
      VkImageView[] attachments = [mSwapchainImageViews[i]];

      VkFramebufferCreateInfo framebufferInfo;
      framebufferInfo.renderPass = mRenderPass;
      framebufferInfo.attachmentCount = 1;
      framebufferInfo.pAttachments = attachments.ptr;
      framebufferInfo.width = mSwapchainExtent.width;
      framebufferInfo.height = mSwapchainExtent.height;
      framebufferInfo.layers = 1;

      assertVk(mDevice.CreateFramebuffer(&framebufferInfo, &mSwapchainFramebuffers[i]));
    }
  }

  void createCommandPool()
  {
    QueueFamilyIndices indices = findQueueFamilies(mPhysicalDevice);

    VkCommandPoolCreateInfo poolInfo;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = indices.graphicsFamily.front;

    assertVk(mDevice.CreateCommandPool(&poolInfo, &mCommandPool));
  }

  void createCommandBuffer()
  {
    VkCommandBufferAllocateInfo allocInfo;
    allocInfo.commandPool = mCommandPool;
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandBufferCount = 1;

    assertVk(mDevice.AllocateCommandBuffers(&allocInfo, &mCommandBuffer));
  }

  void recordCommandBuffer(uint32_t imageIndex)
  {
    VkCommandBufferBeginInfo beginInfo;

    assertVk(mDevice.BeginCommandBuffer(&beginInfo));

    VkRenderPassBeginInfo renderPassInfo;
    renderPassInfo.renderPass = mRenderPass;
    renderPassInfo.framebuffer = mSwapchainFramebuffers[imageIndex];
    renderPassInfo.renderArea.offset = VkOffset2D(0, 0);
    renderPassInfo.renderArea.extent = mSwapchainExtent;

    VkClearValue clearColor = {{[0.0f, 0.0f, 0.0f, 1.0f]}};
    renderPassInfo.clearValueCount = 1;
    renderPassInfo.pClearValues = &clearColor;

    // START RENDERING
    mDevice.CmdBeginRenderPass(&renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
    mDevice.CmdBindPipeline(VK_PIPELINE_BIND_POINT_GRAPHICS, mGraphicsPipeline);

    VkViewport viewport = {
      x: 0.0f, y: 0.0f, width: cast(float) mSwapchainExtent.width, height: cast(float) mSwapchainExtent.height,
      minDepth: 0.0f, maxDepth: 1.0f,
    };

    mDevice.CmdSetViewport(0, 1, &viewport);

    VkRect2D scissor;
    scissor.offset = VkOffset2D(0, 0);
    scissor.extent = mSwapchainExtent;
    mDevice.CmdSetScissor(0, 1, &scissor);

    mDevice.CmdDraw(3, 1, 0, 0);
    mDevice.CmdEndRenderPass();
    // END RENDERING

    assertVk(mDevice.EndCommandBuffer());
  }

  void createSyncObjects()
  {
    VkSemaphoreCreateInfo semaphoreInfo;
    VkFenceCreateInfo fenceInfo;
    fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;

    assertVk(mDevice.CreateSemaphore(&semaphoreInfo, &mImageAvailableSemaphore));
    assertVk(mDevice.CreateSemaphore(&semaphoreInfo, &mRenderFinishedSemaphore));
    assertVk(mDevice.CreateFence(&fenceInfo, &mInFlightFence));
  }

  void drawFrame()
  {
    mDevice.WaitForFences(1, &mInFlightFence, VK_TRUE, uint64_t.max);
    mDevice.ResetFences(1, &mInFlightFence);

    uint32_t imageIndex;
    VkResult result = mDevice.AcquireNextImageKHR(mSwapchain, uint64_t.max,
      mImageAvailableSemaphore, VK_NULL_HANDLE, &imageIndex);

    assertVk(result);

    mDevice.commandBuffer = mCommandBuffer;
    mDevice.ResetCommandBuffer(0);
    recordCommandBuffer(imageIndex);

    VkSubmitInfo submitInfo;
    VkSemaphore[] waitSemaphores = [mImageAvailableSemaphore];
    VkPipelineStageFlags[] waitStages = [
      VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
    ];

    submitInfo.waitSemaphoreCount = 1;
    submitInfo.pWaitSemaphores = waitSemaphores.ptr;
    submitInfo.pWaitDstStageMask = waitStages.ptr;

    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &mCommandBuffer;

    VkSemaphore[] signalSemaphores = [mRenderFinishedSemaphore];
    submitInfo.signalSemaphoreCount = 1;
    submitInfo.pSignalSemaphores = signalSemaphores.ptr;

    assertVk(vkQueueSubmit(mGraphicsQueue, 1, &submitInfo, mInFlightFence));

    VkPresentInfoKHR presentInfo;
    presentInfo.waitSemaphoreCount = 1;
    presentInfo.pWaitSemaphores = signalSemaphores.ptr;

    VkSwapchainKHR[] swapchains = [mSwapchain];
    presentInfo.swapchainCount = 1;
    presentInfo.pSwapchains = swapchains.ptr;
    presentInfo.pImageIndices = &imageIndex;

    assertVk(vkQueuePresentKHR(mPresentQueue, &presentInfo));
  }

  VkShaderModule createShaderModule(const ref char[] code)
  {
    VkShaderModuleCreateInfo createInfo;
    createInfo.codeSize = code.length;
    createInfo.pCode = cast(uint*) code.ptr;

    VkShaderModule shaderModule;
    assertVk(mDevice.CreateShaderModule(&createInfo, &shaderModule));

    return shaderModule;
  }

  VkSurfaceFormatKHR chooseSwapSurfaceFormat(const ref VkSurfaceFormatKHR[] availableFormats)
  {
    foreach (const ref availableFormat; availableFormats)
    {
      if (availableFormat.format == VK_FORMAT_B8G8R8A8_SRGB
        && availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
      {
        return availableFormat;
      }
    }

    return availableFormats[0];
  }

  VkPresentModeKHR chooseSwapPresentMode(const ref VkPresentModeKHR[] availablePresentModes)
  {
    foreach (const ref availablePresentMode; availablePresentModes)
    {
      if (availablePresentMode == VK_PRESENT_MODE_MAILBOX_KHR)
      {
        return availablePresentMode;
      }
    }

    return VK_PRESENT_MODE_FIFO_KHR;
  }

  VkExtent2D chooseSwapExtent(const ref VkSurfaceCapabilitiesKHR capabilities)
  {
    if (capabilities.currentExtent.width != uint32_t.max)
    {
      return capabilities.currentExtent;
    }

    int width, height;
    glfwGetFramebufferSize(mWindow, &width, &height);

    auto actualExtent = VkExtent2D(width, height);

    actualExtent.width = clamp(actualExtent.width,
      capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
    actualExtent.height = clamp(actualExtent.height,
      capabilities.minImageExtent.height, capabilities.maxImageExtent.height);

    return actualExtent;
  }

  SwapchainSupportDetails querySwapchainSupport(VkPhysicalDevice device)
  {
    SwapchainSupportDetails details;

    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, mSurface, &details.capabilities);

    uint32_t formatCount;
    vkGetPhysicalDeviceSurfaceFormatsKHR(device, mSurface, &formatCount, null);

    if (formatCount != 0)
    {
      details.formats.length = formatCount;
      vkGetPhysicalDeviceSurfaceFormatsKHR(device, mSurface, &formatCount, details.formats.ptr);
    }

    uint32_t presentModeCount;
    vkGetPhysicalDeviceSurfacePresentModesKHR(device, mSurface, &presentModeCount, null);

    if (presentModeCount != 0)
    {
      details.presentModes.length = formatCount;
      vkGetPhysicalDeviceSurfacePresentModesKHR(device, mSurface,
        &presentModeCount, details.presentModes.ptr);
    }

    return details;
  }

  bool isDeviceSuitable(VkPhysicalDevice device)
  {
    QueueFamilyIndices indices = findQueueFamilies(device);
    bool extensionsSupported = checkDeviceExtensionSupport(device);
    bool swapchainAdequate = false;

    if (extensionsSupported)
    {
      SwapchainSupportDetails swapchainSupport = querySwapchainSupport(device);
      swapchainAdequate = swapchainSupport.formats.length > 0
        && swapchainSupport.presentModes.length > 0;
    }

    return indices.isComplete && extensionsSupported && swapchainAdequate;
  }

  bool checkDeviceExtensionSupport(VkPhysicalDevice device)
  {
    uint32_t extensionCount;
    vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, null);

    auto availableExtensions = new VkExtensionProperties[extensionCount];
    vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, availableExtensions.ptr);

    auto requiredExtensions = redBlackTree!(strcmp, const char*)(deviceExtensions);
    foreach (VkExtensionProperties availableExtension; availableExtensions)
    {
      requiredExtensions.removeKey(toStringz(availableExtension.extensionName));
    }

    return requiredExtensions.empty;
  }

  QueueFamilyIndices findQueueFamilies(VkPhysicalDevice device)
  {
    QueueFamilyIndices indices;

    uint32_t queueFamilyCount;
    vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);

    VkQueueFamilyProperties[] queueFamilies = new VkQueueFamilyProperties[](queueFamilyCount);
    vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);

    foreach (i, queueFamily; queueFamilies)
    {
      if (queueFamily.queueFlags & VK_QUEUE_GRAPHICS_BIT)
        indices.graphicsFamily = cast(uint) i;

      VkBool32 presentSupport = false;
      vkGetPhysicalDeviceSurfaceSupportKHR(device, cast(uint) i, mSurface, &presentSupport);

      if (presentSupport)
        indices.presentFamily = cast(uint) i;

      if (indices.isComplete)
        break;
    }

    return indices;
  }

  debug
  {
    bool checkValidationLayerSupport()
    {
      uint32_t layer_count;
      vkEnumerateInstanceLayerProperties(&layer_count, null);

      VkLayerProperties[] available_layers = new VkLayerProperties[layer_count];
      vkEnumerateInstanceLayerProperties(&layer_count, available_layers.ptr);

      foreach (const ref layer_name; validationLayers)
      {
        bool layer_found = false;
        foreach (const ref layer_property; available_layers)
        {
          if (strcmp(layer_name, toStringz(layer_property.layerName)) == 0)
          {
            layer_found = true;
            break;
          }
        }

        if (!layer_found)
        {
          return false;
        }
      }

      return true;
    }

    void populateDebugMessengerCreateInfo(ref VkDebugUtilsMessengerCreateInfoEXT createInfo)
    {
      // Reset the struct
      createInfo = VkDebugUtilsMessengerCreateInfoEXT();

      // Fill it out again
      createInfo.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
      createInfo.messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT
        | VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT
        | VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
      createInfo.messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT
        | VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT
        | VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
      createInfo.pfnUserCallback = &debugCallback;
      createInfo.pUserData = null;
    }

    void setupDebugMessenger()
    {
      VkDebugUtilsMessengerCreateInfoEXT createInfo;
      populateDebugMessengerCreateInfo(createInfo);

      assertVk(createDebugUtilsMessengerEXT(mInstance, &createInfo, null, &mDebugMessenger));
    }
  }
}

const(char*)[] getRequiredExtensions()
{
  uint32_t glfwExtensionCount = 0;
  const(char*)* glfwExtensions;
  glfwExtensions = glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

  const(char*)[] extensions = glfwExtensions[0 .. glfwExtensionCount].dup;
  debug extensions ~= VK_EXT_DEBUG_UTILS_EXTENSION_NAME;

  return extensions;
}
