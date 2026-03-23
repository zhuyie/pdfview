#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace pdfview::core {

enum class AnnotationKind : std::uint8_t {
  Highlight,
  Underline,
  Rectangle,
};

struct Point {
  float x = 0.0f;
  float y = 0.0f;
};

struct Rect {
  float x = 0.0f;
  float y = 0.0f;
  float width = 0.0f;
  float height = 0.0f;
};

struct Quad {
  Point p1;
  Point p2;
  Point p3;
  Point p4;
};

struct Color {
  std::uint8_t r = 255;
  std::uint8_t g = 255;
  std::uint8_t b = 0;
  std::uint8_t a = 96;
};

struct Annotation {
  std::string id;
  int page_index = 0;
  AnnotationKind kind = AnnotationKind::Highlight;
  Color color;
  std::vector<Quad> quads;
  Rect rect;
  std::string author;
  std::string created_at;
  std::string modified_at;
};

}  // namespace pdfview::core
