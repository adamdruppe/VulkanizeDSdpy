# VulkanizeD

Hey everyone, this is a sample repo that is my attempt at going through the [Vulkan learning tutorial PDF](https://vulkan-tutorial.com/resources/vulkan_tutorial_en.pdf) and converting it to the D programming language.

Eventually I plan to have all chapters included, but for right now, this only goes through page 135 in the tutorial which is where we use hardcoded variables in the shader to define the Triangle. In order to see all subsequent chapters, I plan on splitting this work up into branches to easily follow along with the book.

## Getting Setup

In order to get setup, you need a couple of prerequisites.

1. The [Vulkan SDK](https://www.lunarg.com/vulkan-sdk/)
2. If you are on Windows, you will need [glfw3 dll and lib files](https://www.glfw.org/) in the root directory. I have not tested this on other platforms yet, but my understanding is that having glfw3 installed for your user in a Unix environment should be sufficient.
3. You will need `glslc` and will need to run the following commands from the root directory to compile the shaders
    1. `cd ./shaders`
    2. `glslc shader.frag -o frag.spv`
    3. `glslc shader.vert -o vert.spv`

## Running the project

Assuming you have `dub` installed on your machine, just run `dub run --build=release` and enjoy your triangle!