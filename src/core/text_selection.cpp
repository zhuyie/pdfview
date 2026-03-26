#include "core/text_selection.h"

#include <algorithm>
#include <cctype>

namespace pdfview {
namespace core {

namespace {

bool IsCjkCodepoint(unsigned int codepoint) {
  return (codepoint >= 0x3400 && codepoint <= 0x4DBF) ||
         (codepoint >= 0x4E00 && codepoint <= 0x9FFF) ||
         (codepoint >= 0xF900 && codepoint <= 0xFAFF) ||
         (codepoint >= 0x20000 && codepoint <= 0x2A6DF) ||
         (codepoint >= 0x2A700 && codepoint <= 0x2B73F) ||
         (codepoint >= 0x2B740 && codepoint <= 0x2B81F) ||
         (codepoint >= 0x2B820 && codepoint <= 0x2CEAF) ||
         (codepoint >= 0x2CEB0 && codepoint <= 0x2EBEF) ||
         (codepoint >= 0x30000 && codepoint <= 0x3134F);
}

bool IsCjkPunctuationCodepoint(unsigned int codepoint) {
  return (codepoint >= 0x3000 && codepoint <= 0x303F) ||
         (codepoint >= 0xFF00 && codepoint <= 0xFF0F) ||
         (codepoint >= 0xFF1A && codepoint <= 0xFF20) ||
         (codepoint >= 0xFF3B && codepoint <= 0xFF40) ||
         (codepoint >= 0xFF5B && codepoint <= 0xFF65);
}

bool IsAsciiCodepoint(unsigned int codepoint) {
  return codepoint <= 0x7F;
}

bool IsAsciiWordCodepoint(unsigned int codepoint) {
  if (!IsAsciiCodepoint(codepoint)) {
    return false;
  }

  const unsigned char ascii = static_cast<unsigned char>(codepoint);
  return std::isalnum(ascii) || ascii == '_';
}

bool IsAsciiSymbolCodepoint(unsigned int codepoint) {
  if (!IsAsciiCodepoint(codepoint)) {
    return false;
  }

  const unsigned char ascii = static_cast<unsigned char>(codepoint);
  return std::ispunct(ascii) != 0 && ascii != '_';
}

bool IsNonAsciiWordCodepoint(unsigned int codepoint) {
  return codepoint > 0x7F && !IsCjkPunctuationCodepoint(codepoint);
}

bool IsNonAsciiSymbolCodepoint(unsigned int codepoint) {
  return codepoint > 0x7F && IsCjkPunctuationCodepoint(codepoint);
}

}  // namespace

bool is_word_codepoint(unsigned int codepoint) {
  return IsAsciiWordCodepoint(codepoint) ||
         IsAsciiSymbolCodepoint(codepoint) ||
         IsNonAsciiWordCodepoint(codepoint) ||
         IsNonAsciiSymbolCodepoint(codepoint);
}

TextCharRange word_char_range_from_text(const std::vector<unsigned int>& codepoints,
                                        int char_index) {
  TextCharRange range;
  if (char_index < 0 || char_index >= static_cast<int>(codepoints.size())) {
    return range;
  }

  if (!is_word_codepoint(codepoints[char_index])) {
    return range;
  }

  if (IsNonAsciiSymbolCodepoint(codepoints[char_index])) {
    range.start_index = char_index;
    range.count = 1;
    return range;
  }

  const bool target_is_ascii_word = IsAsciiWordCodepoint(codepoints[char_index]);
  const bool target_is_ascii_symbol = IsAsciiSymbolCodepoint(codepoints[char_index]);
  const bool target_is_non_ascii_word = IsNonAsciiWordCodepoint(codepoints[char_index]);
  const bool target_is_non_ascii_symbol = IsNonAsciiSymbolCodepoint(codepoints[char_index]);
  int start_index = char_index;
  while (start_index > 0 &&
         is_word_codepoint(codepoints[start_index - 1]) &&
         IsAsciiWordCodepoint(codepoints[start_index - 1]) == target_is_ascii_word &&
         IsAsciiSymbolCodepoint(codepoints[start_index - 1]) == target_is_ascii_symbol &&
         IsNonAsciiWordCodepoint(codepoints[start_index - 1]) == target_is_non_ascii_word &&
         IsNonAsciiSymbolCodepoint(codepoints[start_index - 1]) == target_is_non_ascii_symbol) {
    --start_index;
  }

  int end_index = char_index + 1;
  while (end_index < static_cast<int>(codepoints.size()) &&
         is_word_codepoint(codepoints[end_index]) &&
         IsAsciiWordCodepoint(codepoints[end_index]) == target_is_ascii_word &&
         IsAsciiSymbolCodepoint(codepoints[end_index]) == target_is_ascii_symbol &&
         IsNonAsciiWordCodepoint(codepoints[end_index]) == target_is_non_ascii_word &&
         IsNonAsciiSymbolCodepoint(codepoints[end_index]) == target_is_non_ascii_symbol) {
    ++end_index;
  }

  range.start_index = start_index;
  range.count = end_index - start_index;
  return range;
}

TextCharRange make_text_char_range(int anchor_index, int focus_index) {
  TextCharRange range;
  if (anchor_index < 0 || focus_index < 0 || anchor_index == focus_index) {
    return range;
  }

  range.start_index = std::min(anchor_index, focus_index);
  range.count = std::max(anchor_index, focus_index) - range.start_index + 1;
  return range;
}

bool page_point_from_page_view_point(float view_x,
                                     float view_y,
                                     const PageSize& page_size,
                                     const ViewRect& page_frame,
                                     float* page_x,
                                     float* page_y) {
  if (page_x == NULL || page_y == NULL || page_size.width <= 0.0f ||
      page_size.height <= 0.0f || page_frame.width <= 0.0f ||
      page_frame.height <= 0.0f) {
    return false;
  }

  const float scale_x = page_frame.width / page_size.width;
  const float scale_y = page_frame.height / page_size.height;
  if (scale_x <= 0.0f || scale_y <= 0.0f) {
    return false;
  }

  *page_x = std::max(0.0f, std::min(view_x / scale_x, page_size.width));
  *page_y =
      std::max(0.0f, std::min(page_size.height - (view_y / scale_y), page_size.height));
  return true;
}

std::vector<ViewRect> page_text_rects_to_page_view_rects(
    const std::vector<PageTextRect>& rects,
    const PageSize& page_size,
    const ViewRect& page_frame) {
  std::vector<ViewRect> view_rects;
  if (page_size.width <= 0.0f || page_size.height <= 0.0f ||
      page_frame.width <= 0.0f || page_frame.height <= 0.0f) {
    return view_rects;
  }

  const float scale_x = page_frame.width / page_size.width;
  const float scale_y = page_frame.height / page_size.height;
  for (size_t index = 0; index < rects.size(); ++index) {
    const PageTextRect& rect = rects[index];
    ViewRect view_rect;
    view_rect.x = rect.left * scale_x;
    view_rect.y = (page_size.height - rect.top) * scale_y;
    view_rect.width = std::max(0.0f, rect.right - rect.left) * scale_x;
    view_rect.height = std::max(0.0f, rect.top - rect.bottom) * scale_y;
    if (view_rect.width <= 0.0f || view_rect.height <= 0.0f) {
      continue;
    }
    if (view_rect.width < 5.0f) {
      const float expansion = (5.0f - view_rect.width) * 0.5f;
      view_rect.x = std::max(0.0f, view_rect.x - expansion);
      view_rect.width = 5.0f;
    }
    if (view_rect.height < 5.0f) {
      const float expansion = (5.0f - view_rect.height) * 0.5f;
      view_rect.y = std::max(0.0f, view_rect.y - expansion);
      view_rect.height = 5.0f;
    }
    view_rects.push_back(view_rect);
  }

  return view_rects;
}

}  // namespace core
}  // namespace pdfview
