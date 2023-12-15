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

namespace IMG
{
    class TextureHandle
    {
        TextureHandle(UI::Texture@ texture = null)
        {
            @Texture = @texture;
        }
        // Null if texture is pending load
        UI::Texture@ Texture;
        bool HasLoadFailed = false;
    }
    
    namespace _
    {
        class TextureLoadRequest
        {
            TextureLoadRequest(TextureHandle@ handle, const string&in filepath, int desiredWidth, int desiredHeight)
            {
                @Handle = @handle;
                Filepath = filepath;
                DesiredWidth = desiredWidth;
                DesiredHeight = desiredHeight;
            }
            
            TextureHandle@ Handle;
            string Filepath;
            int DesiredWidth;
            int DesiredHeight;
        }
        
        class SizeRange
        {
            SizeRange(int begin = -1, int end = -1)
            {
                Begin = begin;
                End = end;
            }
            
            SizeRange& opAssign(const SizeRange&in other)
            {
                Begin = other.Begin;
                End = other.End;
                return this;
            }
            
            bool Contains(int val) const
            {
                return (Begin < 0 || val >= Begin) && (End < 0 || (val > 0 && val <= End));
            }
            
            int Compare(int val) const
            {
                if (Begin >= 0 && val >= 0 && val < Begin)
                {
                    return -1;
                }
                if (End >= 0 && (val < 0 || val > End))
                {
                    return 1;
                }
                return 0;
            }
            
            int Begin;
            int End;
        }

        class MipMapTextureLevel
        {
            MipMapTextureLevel(UI::Texture@ texture, SizeRange widthRange, SizeRange heightRange)
            {
                @Texture = @texture;
                WidthRange = widthRange;
                HeightRange = heightRange;
            }
            
            UI::Texture@ Texture;
            SizeRange WidthRange;
            SizeRange HeightRange;
            
            bool Matches(int desiredWidth, int desiredHeight)
            {
                return WidthRange.Contains(desiredWidth) || HeightRange.Contains(desiredHeight);
            }
        }

        class MipMapTextureContainer
        {
            array<MipMapTextureLevel@> Levels;
            
            MipMapTextureLevel@ FindLevel(int desiredWidth, int desiredHeight)
            {
                for (uint i = 0; i < Levels.Length; ++i)
                {
                    if (Levels[i].Matches(desiredWidth, desiredHeight))
                    {
                        return @Levels[i];
                    }
                }
                return null;
            }
        }
    }

    class TextureManager
    {
        TextureHandle@ RequestTexture(const string&in filepath, int desiredWidth = -1, int desiredHeight = -1)
        {
            UI::Texture@ texture = GetLoadedTexture(filepath, desiredWidth, desiredHeight);
            if (texture is null)
            {
                return RequestTextureLoad(filepath, desiredWidth, desiredHeight);
            }
            
            return TextureHandle(@texture);
        }
        
        void ProcessOneLoadRequest()
        {
            while (!TextureLoadRequests.IsEmpty())
            {
                _::TextureLoadRequest@ request = TextureLoadRequests[0];
                TextureLoadRequests.RemoveAt(0);
                
                UI::Texture@ texture = GetLoadedTexture(request.Filepath, request.DesiredWidth, request.DesiredHeight);
                if (texture !is null)
                {
                    @request.Handle.Texture = @texture;
                    continue;
                }
                
                if (!IO::FileExists(request.Filepath))
                {
                    request.Handle.HasLoadFailed = true;
                    continue;
                }
                
                if (!IMG::IsDds(request.Filepath))
                {
                    IO::File file(request.Filepath, IO::FileMode::Read);
                    @request.Handle.Texture = UI::LoadTexture(file.Read(file.Size()));
                    if (request.Handle.Texture is null)
                    {
                        request.Handle.HasLoadFailed = true;
                        continue; // could break
                    }
                    
                    StoreLevel(request.Filepath, @request.Handle.Texture, _::SizeRange(), _::SizeRange());
                    break;
                }
                
                IMG::DdsContainer@ ddsContainer = IMG::LoadDdsContainer(request.Filepath);
                if (ddsContainer is null || ddsContainer.Images.IsEmpty())
                {
                    request.Handle.HasLoadFailed = true;
                    continue; // could break
                }
                
                auto@ ddsImage = ddsContainer.Images[0];
                int bestLevel = ddsImage.GetBestLevel(request.DesiredWidth, request.DesiredHeight);
                
                int3 levelSizeRangeBegin(-1, -1, -1);
                if (bestLevel != ddsImage.GetMaxLevel())
                {
                    levelSizeRangeBegin = ddsImage.GetLevelSize(bestLevel + 1) + int3(1, 1, 1);
                }
                
                int3 levelSizeRangeEnd(-1, -1, -1);
                if (bestLevel > 0)
                {
                    levelSizeRangeEnd = ddsImage.GetLevelSize(bestLevel);
                }
                
                @request.Handle.Texture = UI::LoadTexture(ddsImage.DecompressLevel(bestLevel).ToBitmap());
                if (request.Handle.Texture is null)
                {
                    request.Handle.HasLoadFailed = true;
                    continue; // could break
                }
                
                _::SizeRange widthRange(levelSizeRangeBegin.x, levelSizeRangeEnd.x);
                _::SizeRange heightRange(levelSizeRangeBegin.y, levelSizeRangeEnd.y);
                StoreLevel(request.Filepath, @request.Handle.Texture, widthRange, heightRange);
                break;
            }
        }
        
        bool HasLoadRequest() const
        {
            return !TextureLoadRequests.IsEmpty();
        }
        
        void ClearTextures(const string&in filepath)
        {
            LoadedMipMapTextureContainers.Delete(filepath);
        }
        
        private TextureHandle@ RequestTextureLoad(const string&in filepath, int desiredWidth = -1, int desiredHeight = -1)
        {
            if (!IO::FileExists(filepath))
            {
                return null;
            }
            
            TextureHandle@ handle = TextureHandle();
            TextureLoadRequests.InsertLast(_::TextureLoadRequest(@handle, filepath, desiredWidth, desiredHeight));
            return @handle;
        }
        
        private UI::Texture@ GetLoadedTexture(const string&in filepath, int desiredWidth = -1, int desiredHeight = -1)
        {
            if (!LoadedMipMapTextureContainers.Exists(filepath))
            {
                return null;
            }
            
            _::MipMapTextureContainer@ container = cast<_::MipMapTextureContainer>(@LoadedMipMapTextureContainers[filepath]);
            _::MipMapTextureLevel@ level = container.FindLevel(desiredWidth, desiredHeight);
            if (level is null)
            {
                return null;
            }
            
            return @level.Texture;
        }
        
        private void StoreLevel(const string&in filepath, UI::Texture@ texture, _::SizeRange widthRange, _::SizeRange heightRange)
        {
            if (!LoadedMipMapTextureContainers.Exists(filepath))
            {
                LoadedMipMapTextureContainers.Set(filepath, _::MipMapTextureContainer());
            }
            
            _::MipMapTextureContainer@ container = cast<_::MipMapTextureContainer>(@LoadedMipMapTextureContainers[filepath]);
            container.Levels.InsertLast(_::MipMapTextureLevel(@texture, widthRange, heightRange));
        }
        
        private dictionary LoadedMipMapTextureContainers;
        private array<_::TextureLoadRequest@> TextureLoadRequests;
    }
}