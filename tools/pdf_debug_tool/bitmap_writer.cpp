#include "bitmap_writer.h"

#include <fstream>

namespace pdfview {
namespace tools {

namespace {

bool WriteUint16LE(std::ofstream* stream, unsigned int value) {
  const unsigned char bytes[2] = {
      static_cast<unsigned char>(value & 0xFFu),
      static_cast<unsigned char>((value >> 8) & 0xFFu),
  };
  stream->write(reinterpret_cast<const char*>(bytes), sizeof(bytes));
  return stream->good();
}

bool WriteUint32LE(std::ofstream* stream, unsigned int value) {
  const unsigned char bytes[4] = {
      static_cast<unsigned char>(value & 0xFFu),
      static_cast<unsigned char>((value >> 8) & 0xFFu),
      static_cast<unsigned char>((value >> 16) & 0xFFu),
      static_cast<unsigned char>((value >> 24) & 0xFFu),
  };
  stream->write(reinterpret_cast<const char*>(bytes), sizeof(bytes));
  return stream->good();
}

bool WriteInt32LE(std::ofstream* stream, int value) {
  return WriteUint32LE(stream, static_cast<unsigned int>(value));
}

}  // namespace

bool write_bitmap_as_bmp(const std::string& output_path, const pdfview::core::Bitmap& bitmap) {
  if (bitmap.width <= 0 || bitmap.height <= 0 || bitmap.stride < bitmap.width * 4 ||
      bitmap.pixels.empty()) {
    return false;
  }

  const unsigned int pixel_data_size = static_cast<unsigned int>(bitmap.width * bitmap.height * 4);
  const unsigned int file_header_size = 14u;
  const unsigned int dib_header_size = 40u;
  const unsigned int pixel_data_offset = file_header_size + dib_header_size;
  const unsigned int file_size = pixel_data_offset + pixel_data_size;

  std::ofstream output(output_path.c_str(), std::ios::binary);
  if (!output.is_open()) {
    return false;
  }

  output.put('B');
  output.put('M');
  if (!WriteUint32LE(&output, file_size) ||
      !WriteUint16LE(&output, 0u) ||
      !WriteUint16LE(&output, 0u) ||
      !WriteUint32LE(&output, pixel_data_offset) ||
      !WriteUint32LE(&output, dib_header_size) ||
      !WriteInt32LE(&output, bitmap.width) ||
      !WriteInt32LE(&output, -bitmap.height) ||
      !WriteUint16LE(&output, 1u) ||
      !WriteUint16LE(&output, 32u) ||
      !WriteUint32LE(&output, 0u) ||
      !WriteUint32LE(&output, pixel_data_size) ||
      !WriteInt32LE(&output, 2835) ||
      !WriteInt32LE(&output, 2835) ||
      !WriteUint32LE(&output, 0u) ||
      !WriteUint32LE(&output, 0u)) {
    return false;
  }

  for (int y = 0; y < bitmap.height; ++y) {
    const size_t row_offset = static_cast<size_t>(y) * static_cast<size_t>(bitmap.stride);
    output.write(reinterpret_cast<const char*>(&bitmap.pixels[row_offset]),
                 static_cast<std::streamsize>(bitmap.width * 4));
    if (!output.good()) {
      return false;
    }
  }

  return true;
}

}  // namespace tools
}  // namespace pdfview
