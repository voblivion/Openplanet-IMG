/**
    MIT License

    Copyright (c) 2023 Victor Evariste Drouin Viallard

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
**/

namespace IMG_Example
{
    // Supports: simple DXT1,3,5 images, with or without mip maps
    // Not yet supported:
    // - cube maps
    // - DXT10 (so no arrays of images)
    // - non-DXT1,3,5 compressions
    
    string Sample_PngImagePath = IO::FromUserGameFolder("Skins/Stadium/ModWork/Image/PlatformGrass_N.png");
    string Sample_DdsImagePath = IO::FromUserGameFolder("Skins/Stadium/ModWork/Image/PlatformIce_D.dds");
    
    IMG::TextureManager@ textureManager;
    bool Setting_IsWindowVisible = true;
    int Setting_ImageDesiredLoadedSize = 64;
    bool Setting_UseDesiredLoadedSizeAsDisplaySize = false;
    int Setting_ImageDisplaySize = 256;
    
    void RenderInterface()
    {
        UI::Begin("IMG_Example", Setting_IsWindowVisible, UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoScrollbar);
        Setting_UseDesiredLoadedSizeAsDisplaySize =
            UI::Checkbox("Use Desired Loaded Size As Display Size", Setting_UseDesiredLoadedSizeAsDisplaySize);
        Setting_ImageDesiredLoadedSize = UI::SliderInt("Image Loaded Size", Setting_ImageDesiredLoadedSize, 1, 2048);
        UI::SameLine();
        UI::BeginDisabled(Setting_UseDesiredLoadedSizeAsDisplaySize);
        Setting_ImageDisplaySize = UI::SliderInt("Image Display Size", Setting_ImageDisplaySize, 1, 2048);
        UI::EndDisabled();
        
        int imageDisplaySize = Setting_UseDesiredLoadedSizeAsDisplaySize ? Setting_ImageDesiredLoadedSize : Setting_ImageDisplaySize;
        
        auto@ pngHandle = textureManager.RequestTexture(
            Sample_PngImagePath, Setting_ImageDesiredLoadedSize, Setting_ImageDesiredLoadedSize);
        if (pngHandle !is null && pngHandle.Texture !is null)
        {
            UI::Image(@pngHandle.Texture, vec2(imageDisplaySize, imageDisplaySize));
        }
        UI::SameLine();
        auto@ ddsHandle = textureManager.RequestTexture(
            Sample_DdsImagePath, Setting_ImageDesiredLoadedSize, Setting_ImageDesiredLoadedSize);
        if (ddsHandle !is null && ddsHandle.Texture !is null)
        {
            UI::Image(@ddsHandle.Texture, vec2(imageDisplaySize, imageDisplaySize));
        }
        
        UI::End();
    }
    
    void Main()
    {
        @textureManager = IMG::TextureManager();
        
        while (true)
        {
            sleep(10);
            textureManager.ProcessOneLoadRequest();
        }
    }
    
    void HowToLoadDdsTextures()
    {
        string filepath = IO::FromUserGameFolder("Skins/Stadium/ModWork/Image/PlatformTech_D.dds");
        
        IMG::DdsContainer@ ddsContainer = IMG::LoadDdsContainer(IO::FromUserGameFolder("Skins/Stadium/ModWork/Image/PlatformTech_D.dds"));
        UI::Texture@ textureLevel3 = ddsContainer.Images[0].DecompressLevel(3).ToTexture();
        UI::Texture@ texture256p = UI::LoadTexture(ddsContainer.Images[0].DecompressSize(256, 256).ToBitmap());
    }
}
