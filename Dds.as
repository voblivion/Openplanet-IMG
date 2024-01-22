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
    class RawImage
    {
        int Width;
        int Height;
        int Depth;
        string Data; // top to bottom, left to right, RGBA
        
        MemoryBuffer@ ToBitmap()
        {
            MemoryBuffer@ target = MemoryBuffer();
            
            // BMP header
            target.Write("BM");
            target.Write(uint(0)); // BMP Size
            target.Write(uint(0)); // Dummy
            target.Write(14 + 40 + 2); // File offset to pixel array
            
            // DIP header
            target.Write(uint(40));
            target.Write(Width);
            target.Write(-Height); // top to bottom
            target.Write(uint16(1)); // Color plane count, must be 1
            target.Write(uint16(32)); // Bit count per pixel
            target.Write(uint(0)); // BI_RGB compression
            target.Write(uint(0)); // Image size
            target.Write(0); // Horizontal resolution
            target.Write(0); // Vertical resolution
            target.Write(uint(0)); // Color palette size
            target.Write(uint(0)); // Important color count
            
            target.Write(uint16(0)); // Padding for 4-byte alignment
            
            // Pixel array
            // TODO: stop being lazy and figure out how to write in RGBA order
            for (int i = 0; i < Data.Length / 4; ++i)
            {
                target.Write(Data[i * 4 + 2]);
                target.Write(Data[i * 4 + 1]);
                target.Write(Data[i * 4 + 0]);
                target.Write(Data[i * 4 + 3]);
            }
            
            return target;
        }
        
        UI::Texture@ ToTexture()
        {
            return UI::LoadTexture(ToBitmap());
        }
    }
    
    enum CompressedFormat
    {
        None,
        RGBA,
        DXT1,
        DXT3,
        DXT5
    }
    
    namespace _
    {
        int Unpack565(int v0, int v1, uint8&out r, uint8&out g, uint8&out b)
        {
            int value = v0 | (v1 << 8);
            r = (value >> 11) & 0x1f;
            g = (value >> 5) & 0x3f;
            b = (value >> 0) & 0x1f;
            r = (r << 3) | (r >> 2);
            g = (g << 2) | (g >> 4);
            b = (b << 3) | (b >> 2);
            return value;
        }
        
        int DecompressDXTColorBlock(bool isDXT1, const string&in sourceData, int colorBlockOffset, array<uint8>& decompressedBlock)
        {
            array<uint8> codes(16);
            int a = Unpack565(sourceData[colorBlockOffset + 0], sourceData[colorBlockOffset + 1], codes[0], codes[1], codes[2]);
            int b = Unpack565(sourceData[colorBlockOffset + 2], sourceData[colorBlockOffset + 3], codes[4], codes[5], codes[6]);
            for (int i = 0; i < 3; ++i)
            {
                int c = codes[0 + i];
                int d = codes[4 + i];
                if (isDXT1 && a <= b)
                {
                    codes[8 + i] = (c + d) / 2;
                    codes[12 + i] = 0;
                }
                else
                {
                    codes[8 + i] = (2 * c + d) / 3;
                    codes[12 + i] = (c + 2 * d) / 3;
                }
            }
            codes[8 + 3] = 255;
            codes[12 + 3] = (isDXT1 && a <= b) ? 0 : 255;
            
            array<uint8> indices(16);
            for (int i = 0; i < 4; ++i)
            {
                uint8 packed = sourceData[colorBlockOffset + 4 + i];
                indices[4 * i + 0] = (packed >> 0) & 3;
                indices[4 * i + 1] = (packed >> 2) & 3;
                indices[4 * i + 2] = (packed >> 4) & 3;
                indices[4 * i + 3] = (packed >> 6) & 3;
            }
            
            for (int i = 0; i < 16; ++i)
            {
                uint8 offset = 4 * indices[i];
                decompressedBlock[4 * i + 0] = codes[offset + 0];
                decompressedBlock[4 * i + 1] = codes[offset + 1];
                decompressedBlock[4 * i + 2] = codes[offset + 2];
            }
            
            return colorBlockOffset + 8;
        }
        
        int DecompressDXT3AlphaBlock(const string&in sourceData, int alphaBlockOffset, array<uint8>& decompressedBlock)
        {
            for (int i = 0; i < 8; ++i)
            {
                uint8 quant = sourceData[alphaBlockOffset + i];
                uint8 low = quant & 0x0f;
                uint8 high = quant & 0xf0;
                decompressedBlock[8 * i + 3] = low | (low << 4);
                decompressedBlock[8 * i + 7] = high | (high >> 4);
            }
            
            return alphaBlockOffset + 8;
        }
        
        int DecompressDXT5AlphaBlock(const string&in sourceData, int alphaBlockOffset, array<uint8>& decompressedBlock)
        {
            int alpha0 = sourceData[alphaBlockOffset + 0];
            int alpha1 = sourceData[alphaBlockOffset + 1];
            
            array<uint8> codes(8);
            codes[0] = alpha0;
            codes[1] = alpha1;
            if (alpha0 <= alpha1)
            {
                for (int i = 1; i < 5; ++i)
                {
                    codes[1 + i] = ((5 - i) * alpha0 + i * alpha1) / 5;
                }
                codes[6] = 0;
                codes[7] = 255;
            }
            else
            {
                for (int i = 1; i < 7; ++i)
                {
                    codes[1 + i] = ((7 - i) * alpha0 + i * alpha1) / 7;
                }
            }
            
            array<uint8> indices(16);
            int k = 2;
            int l = 0;
            for (int i = 0; i < 2; ++i)
            {
                int value = 0;
                for (int j = 0; j < 3; ++j)
                {
                    int byte = sourceData[alphaBlockOffset + (k++)];
                    value |= byte << (8 * j);
                }
                
                for (int j = 0; j < 8; ++j)
                {
                    uint8 index = (value >> (3 * j)) & 0x7;
                    indices[l++] = index;
                }
            }
            
            for (int i = 0; i < 16; ++i)
            {
                decompressedBlock[4 * i + 3] = codes[indices[i]];
            }
            
            return alphaBlockOffset + 8;
        }
        
        int DecompressDXTBlock(CompressedFormat format, const string&in sourceData, int blockOffset, array<uint8>& decompressedBlock)
        {
            if (format == CompressedFormat::DXT3)
            {
                blockOffset = DecompressDXT3AlphaBlock(sourceData, blockOffset, decompressedBlock);
            }
            else if (format == CompressedFormat::DXT5)
            {
                blockOffset = DecompressDXT5AlphaBlock(sourceData, blockOffset, decompressedBlock);
            }
            else
            {
                for (int i = 0; i < 16; ++i)
                {
                    decompressedBlock[4 * i + 3] = 255;
                }
            }
            
            return DecompressDXTColorBlock(format == CompressedFormat::DXT1, sourceData, blockOffset, decompressedBlock);
        }
        
        string DecompressDXTImage(CompressedFormat format, const string&in sourceData, int sourceOffset, int width, int height, int depth)
        {
            // HACK: don't know a better way to create a fixed size byte span that is not an array.
            int pixelDataSize = width * height * 4 * depth;
            MemoryBuffer@ pixelDataBuffer = MemoryBuffer(pixelDataSize);
            string pixelData = pixelDataBuffer.ReadString(pixelDataSize);
            
            int nextYieldCounter = 64 * 64;
            
            int blockOffset = sourceOffset;
            array<uint8> decompressedBlock(16 * 4);
            for (int z = 0; z < depth; ++z)
            {
                int iz = width * height * 4 * z;
                for (int y = 0; y < height; y += 4)
                {
                    for (int x = 0; x < width; x += 4)
                    {
                        blockOffset = DecompressDXTBlock(format, sourceData, blockOffset, decompressedBlock);
                        int decompressedBlockIndex = 0;
                        for (int by = 0; by < 4; ++by)
                        {
                            for (int bx = 0; bx < 4; ++bx)
                            {
                                int ix = x + bx;
                                int iy = y + by;
                                if (ix < width && iy < height)
                                {
                                    uint imageIndex = iz + 4 * (width * iy + ix);
                                    pixelData[imageIndex + 0] = decompressedBlock[decompressedBlockIndex++];
                                    pixelData[imageIndex + 1] = decompressedBlock[decompressedBlockIndex++];
                                    pixelData[imageIndex + 2] = decompressedBlock[decompressedBlockIndex++];
                                    pixelData[imageIndex + 3] = decompressedBlock[decompressedBlockIndex++];
                                }
                                else
                                {
                                    decompressedBlockIndex += 4;
                                }
                            }
                        }
                        
                        nextYieldCounter -= 4;
                        if (nextYieldCounter <= 0)
                        {
                            yield();
                            nextYieldCounter = 64 * 64;
                        }
                    }
                }
            }
            
            return pixelData;
        }
        
        class DdsColorKey // size 8
        {
            void FromBuffer(MemoryBuffer@ source)
            {
                ColorSpaceLowValue = source.ReadUInt32();
                ColorSpaceHighValue = source.ReadUInt32();
            }
            
            uint ColorSpaceLowValue;
            uint ColorSpaceHighValue;
        }
        
        class DdsPixelFormat
        {
            void FromBuffer(MemoryBuffer@ source)
            {
                Size = source.ReadUInt32();
                Flags = source.ReadUInt32();
                FourCC = source.ReadUInt32();
                RGBBitCount = source.ReadUInt32();
                RBitMask = source.ReadUInt32();
                GBitMask = source.ReadUInt32();
                BBitMask = source.ReadUInt32();
                RGBAlphaBitMask = source.ReadUInt32();
            }
            
            uint Size;
            uint Flags;
            uint FourCC;
            uint RGBBitCount;
            uint get_YUVBitCount() const { return RGBBitCount; }
            uint get_ZBufferBitDepth() const { return RGBBitCount; }
            uint get_AlphaBitDepth() const { return RGBBitCount; }
            uint get_LuminanceBitCount() const { return RGBBitCount; }
            uint get_BumpBitCount() const { return RGBBitCount; }
            uint get_PrivateFormatBitCount() const { return RGBBitCount; }
            uint RBitMask;
            uint get_YBitMask() const { return RBitMask; }
            uint get_StencilBitDepth() const { return RBitMask; }
            uint get_LuminanceBitMask() const { return RBitMask; }
            uint get_BumpDuBitMask() const { return RBitMask; }
            uint get_Operations() const { return RBitMask; }
            uint GBitMask;
            uint get_UBitMask() const { return GBitMask; }
            uint get_ZBitMask() const { return GBitMask; }
            uint get_BumpDvBitMask() const { return GBitMask; }
            uint get_FlipAndBltMSTypes() const { return GBitMask; }
            uint BBitMask;
            uint get_VBitMask() const { return BBitMask; }
            uint get_StencilBitMask() const { return BBitMask; }
            uint get_BumpLuminanceBitMask() const { return BBitMask; }
            uint RGBAlphaBitMask;
            uint get_YUVAlphaBitMask() const { return RGBAlphaBitMask; }
            uint get_LuminanceAlphaBitMask() const { return RGBAlphaBitMask; }
            uint get_RGBZBitMask() const { return RGBAlphaBitMask; }
            uint get_YUVZBitMask() const { return RGBAlphaBitMask; }
        }
        
        class DdsHeader
        {
            void FromBuffer(MemoryBuffer@ source)
            {
                Size = source.ReadUInt32();
                Flags = source.ReadUInt32();
                Height = source.ReadUInt32();
                Width = source.ReadUInt32();
                Pitch = source.ReadUInt32();
                BackBufferCount = source.ReadUInt32();
                MipMapCount = source.ReadUInt32();
                AlphaBitDepth = source.ReadUInt32();
                Reserved = source.ReadUInt32();
                Surface = source.ReadUInt32();
                CkDestOverlay.FromBuffer(source);
                CkDestBlt.FromBuffer(source);
                CkSrcOverlay.FromBuffer(source);
                CkSrcBlt.FromBuffer(source);
                PixelFormat.FromBuffer(source);
                Caps = source.ReadUInt32();
                Caps2 = source.ReadUInt32();
                Caps3 = source.ReadUInt32();
                Caps4 = source.ReadUInt32();
                TextureStage = source.ReadUInt32();
            }
            
            uint Size;
            uint Flags;
            uint Height;
            uint Width;
            uint Pitch;
            uint get_LinearSize() const { return Pitch; }
            uint BackBufferCount;
            uint get_Depth() const { return BackBufferCount; }
            uint MipMapCount;
            uint get_RefreshRate() const { return MipMapCount; }
            uint get_SrcVBHandle() const { return MipMapCount; }
            uint AlphaBitDepth;
            uint Reserved;
            uint Surface;
            DdsColorKey CkDestOverlay;
            uint get_EmptyFaceColor() const { return CkDestOverlay.ColorSpaceLowValue; }
            DdsColorKey CkDestBlt;
            DdsColorKey CkSrcOverlay;
            DdsColorKey CkSrcBlt;
            DdsPixelFormat PixelFormat;
            uint get_FVF() const { return PixelFormat.Size; }
            uint Caps;
            uint Caps2;
            uint Caps3;
            uint Caps4;
            uint get_VolumeDepth() const { return Caps4; }
            uint TextureStage;
        }
        
        class DdsHeaderDXT10
        {
            void FromBuffer(MemoryBuffer@ source)
            {
                DxgiFormat = source.ReadUInt32();
                ResourceDimension = source.ReadUInt32();
                MiscFlag = source.ReadUInt32();
                ArraySize = source.ReadUInt32();
                Reserved = source.ReadUInt32();
            }
            
            uint DxgiFormat;
            uint ResourceDimension;
            uint MiscFlag;
            uint ArraySize;
            uint Reserved;
        }
        
        const uint FOURCC_DXT1 = 827611204; // DXT1
        const uint FOURCC_DXT2 = 844388420; // DXT2
        const uint FOURCC_DXT3 = 861165636; // DXT3
        const uint FOURCC_DXT4 = 877942852; // DXT4
        const uint FOURCC_DXT5 = 894720068; // DXT5
        const uint FOURCC_DX10 = 808540228; // DX10
        const uint FOURCC_ETC1 = 826496069; // ETC1
        const uint FOURCC_ETC2 = 843273285; // ETC2
        const uint FOURCC_ET2A = 1093817413; // ET2A
        
        const uint DXGI_FORMAT_R8G8B8A8_UNORM = 28;
        const uint DXGI_FORMAT_R8G8B8A8_UNORM_SRGB = 26;
        const uint DXGI_FORMAT_BC1_UNORM = 71;
        const uint DXGI_FORMAT_BC1_UNORM_SRGB = 72;
        const uint DXGI_FORMAT_BC2_UNORM = 74;
        const uint DXGI_FORMAT_BC2_UNORM_SRGB = 75;
        const uint DXGI_FORMAT_BC3_UNORM = 77;
        const uint DXGI_FORMAT_BC3_UNORM_SRGB = 78;
        
        const uint CAPS2_CUBEMAP_ALL_FACES = 64512;
        
        string PeekString(MemoryBuffer@ source, int size)
        {
            string str = source.ReadString(size);
            source.Seek(size, -1);
            return str;
        }
        
        bool IsDdsMagic(const string&in magic)
        {
            return magic == "DDS ";
        }
        
        int Min(int lhs, int rhs)
        {
            return lhs < rhs ? lhs : rhs;
        }
        
        int Max(int lhs, int rhs)
        {
            return lhs > rhs ? lhs : rhs;
        }
        
        int Clamp(int value, int min, int max)
        {
            return Min(Max(min, value), max);
        }
    }
    
    class DdsImage
    {
        DdsImage(int width, int height, int depth, CompressedFormat format, int mipMapCount, const string&in data)
        {
            _Width = width;
            _Height = height;
            _Depth = depth;
            _Format = format;
            _MipMapCount = mipMapCount;
            _Data = data;
        }
        
        private int _Width;
        private int _Height;
        private int _Depth;
        private CompressedFormat _Format;
        private int _MipMapCount;
        private string _Data;
        
        int3 GetLevelSize(int mipMapLevel) const
        {
            int width = _Width;
            int height = _Height;
            int depth = _Depth;
            for (int i = 0; i < mipMapLevel; ++i)
            {
                width = _::Max(1, width / 2);
                height = _::Max(1, height / 2);
                depth = _::Max(1, depth / 2);
            }
            return int3(width, height, depth);
        }
        
        int GetMaxLevel() const
        {
            return _MipMapCount - 1;
        }
        
        int GetBestLevel(int minDesiredWidth, int minDesiredHeight, int minDesiredDepth = 0) const
        {
            minDesiredWidth = minDesiredWidth < 0 ? _Width : minDesiredWidth;
            minDesiredHeight = minDesiredHeight < 0 ? _Height : minDesiredHeight;
            minDesiredDepth = minDesiredDepth < 0 ? _Depth : minDesiredDepth;
            for (int level = 1; level < _MipMapCount; ++level)
            {
                int3 levelSize = GetLevelSize(level);
                if (levelSize.x < minDesiredWidth || levelSize.y < minDesiredHeight || levelSize.z < minDesiredDepth)
                {
                    return level - 1;
                }
            }
            return GetMaxLevel();
        }
        
        RawImage@ DecompressLevel(int mipMapLevel)
        {
            switch (_Format)
            {
            case DXT1:
            case DXT3:
            case DXT5:
            {
                RawImage@ rawImage = RawImage();
                rawImage.Width = _Width;
                rawImage.Height = _Height;
                rawImage.Depth = _Depth;
                
                int blockSize = _Format == CompressedFormat::DXT1 ? 8 : 16;
                int dataOffset = 0;
                for (int i = 0; i < mipMapLevel; ++i)
                {
                    uint blockCountWidth = (rawImage.Width + 3) / 4;
                    uint blockCountHeight = (rawImage.Height + 3) / 4;
                    dataOffset += blockSize * blockCountWidth * blockCountHeight * rawImage.Depth;
                    
                    rawImage.Width = _::Max(1, rawImage.Width / 2);
                    rawImage.Height = _::Max(1, rawImage.Height / 2);
                    rawImage.Depth = _::Max(1, rawImage.Depth / 2);
                }
                
                rawImage.Data = _::DecompressDXTImage(_Format, _Data, dataOffset, rawImage.Width, rawImage.Height, rawImage.Depth);
                return @rawImage;
            }
            default:
                warn("Not implemented: only DXT1,2,3 compressions are supported.");
                return null;
            }
        }
        
        RawImage@ DecompressSize(int minWidth, int minHeight, int minDepth = 0)
        {
            return DecompressLevel(GetBestLevel(minWidth, minHeight, minDepth));
        }
    }
    
    class DdsContainer
    {
        bool IsCubeMap;
        array<DdsImage@> Images;
    }
    
    bool IsDds(MemoryBuffer@ source)
    {
        return _::IsDdsMagic(_::PeekString(source, 4));
    }
    
    bool IsDds(const string&in filepath)
    {
        IO::File file(filepath, IO::FileMode::Read);
        if (file.Size() < 128)
        {
            return false;
        }
        
        MemoryBuffer@ buffer = file.Read(4);
        string magic = buffer.ReadString(4);
        return _::IsDdsMagic(magic);
    }
    
    DdsContainer@ LoadDdsContainer(MemoryBuffer@ source)
    {
        if (source.GetSize() < 128)
        {
            warn("Invalid DDS format: source is too small to fit DDS header.");
            return null;
        }
        
        string magic = source.ReadString(4);
        if (!_::IsDdsMagic(magic))
        {
            warn("Invalid DDS format: magic is not 'DDS '.");
            return null;
        }
        
        _::DdsHeader header;
        header.FromBuffer(@source);
        
        CompressedFormat format = CompressedFormat::None;
        uint fourCC = header.PixelFormat.FourCC;
        bool isSRGB = false;
        uint imageCount = 1;
        
        _::DdsHeaderDXT10 headerDXT10;
        switch (header.PixelFormat.FourCC)
        {
        case _::FOURCC_DXT1:
            format = CompressedFormat::DXT1;
            break;
        case _::FOURCC_DXT3:
            format = CompressedFormat::DXT3;
            break;
        case _::FOURCC_DXT5:
            format = CompressedFormat::DXT5;
            break;
        case _::FOURCC_DX10:
            headerDXT10.FromBuffer(@source);
            imageCount = headerDXT10.ArraySize;
            
            switch (headerDXT10.DxgiFormat)
            {
            case _::DXGI_FORMAT_BC1_UNORM_SRGB:
                isSRGB = true;
            case _::DXGI_FORMAT_BC1_UNORM:
                format = CompressedFormat::DXT1;
                break;
            case _::DXGI_FORMAT_BC2_UNORM_SRGB:
                isSRGB = true;
            case _::DXGI_FORMAT_BC2_UNORM:
                format = CompressedFormat::DXT3;
                break;
            case _::DXGI_FORMAT_BC3_UNORM_SRGB:
                isSRGB = true;
            case _::DXGI_FORMAT_BC3_UNORM:
                format = CompressedFormat::DXT5;
                break;
            case _::DXGI_FORMAT_R8G8B8A8_UNORM_SRGB:
                isSRGB = true;
            case _::DXGI_FORMAT_R8G8B8A8_UNORM:
            {
                const uint rgbBitCount = header.PixelFormat.RGBBitCount;
                if ((rgbBitCount != 16) and (rgbBitCount != 24) and (rgbBitCount != 32))
                {
                    warn("Invalid DDS format: pixel byte size is invalid.");
                    return null;
                }
                format = CompressedFormat::RGBA;
                warn("Not implemented: uncompressed DDS is not supported.");
                return null;
            }
            default:
                warn("Invalid DDS format: DXGI format is not recognized.");
                return null;
            }
            
            break;
        default:
            warn("Not implemented: only DXT1,3,5,10 FourCCs are supported.");
            return null;
        }
        
        bool isCubeMap = (header.Caps2 & _::CAPS2_CUBEMAP_ALL_FACES) != 0;
        if (isCubeMap)
        {
            imageCount = 6;
        }
        
        int dataSize = 0;
        int depth = _::Max(1, header.Depth);
        if (format != CompressedFormat::RGBA)
        {
            uint blockSize = format == CompressedFormat::DXT1 ? 8 : 16;
            uint blockCountWidth = (header.Width + 3) / 4;
            uint blockCountHeight = (header.Height + 3) / 4;
            dataSize = blockSize * blockCountWidth * blockCountHeight * depth;
            
            uint x = header.Width;
            uint y = header.Height;
            uint z = depth;
            for (uint level = header.MipMapCount; level > 1; --level)
            {
                x /= 2;
                y /= 2;
                z /= 2;
                blockCountWidth = (_::Max(1, x) + 3) / 4;
                blockCountHeight = (_::Max(1, y) + 3) / 4;
                dataSize += blockSize * blockCountWidth * blockCountHeight * _::Max(1, z);
            }
        }
        else
        {
            // Note: there is an early return above, this code is never reached for now.
            dataSize = (header.PixelFormat.RGBBitCount / 8) * header.Width * header.Height * depth;
            uint x = header.Width;
            uint y = header.Height;
            uint z = depth;
            for (uint level = header.MipMapCount; level > 1; --level)
            {
                x /= 2;
                y /= 2;
                z /= 2;
                dataSize += (header.PixelFormat.RGBBitCount / 8) * _::Max(1, x) * _::Max(1, y) * _::Max(1, z);
            }
        }
        
        DdsContainer@ ddsContainer = DdsContainer();
        ddsContainer.IsCubeMap = isCubeMap;
        for (uint imageIndex = 0; imageIndex < imageCount; ++imageIndex)
        {
            DdsImage@ image = DdsImage(
                _::Max(1, header.Width),
                _::Max(1, header.Height),
                _::Max(1, header.Depth),
                format,
                _::Max(1, header.MipMapCount),
                source.ReadString(dataSize));
            
            ddsContainer.Images.InsertLast(@image);
        }
        
        return @ddsContainer;
    }
    
    DdsContainer@ LoadDdsContainer(const string&in filepath)
    {
        IO::File file(filepath, IO::FileMode::Read);
        return LoadDdsContainer(file.Read(file.Size()));
    }
}
