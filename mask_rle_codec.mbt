///|
/// Reads the COCO compressed counts string (signed 5-bit groups, ASCII 48–111).
/// Counts from the fourth run onward are differences from two runs earlier.
/// At most seven characters per run are accepted for Int-sized masks.
pub fn CocoRle::from_compressed(
  height : Int,
  width : Int,
  encoded : String,
) -> CocoRle raise EvalError {
  let pixels = rle_pixel_count(height, width)
  let counts : Array[Int] = []
  let mut offset = 0
  let mut total = 0L
  while offset < encoded.length() {
    let start = offset
    let mut value = 0L
    let mut shift = 0
    while true {
      if offset >= encoded.length() {
        raise InvalidInput("mask RLE counts truncated at character \{offset}")
      }
      let code = encoded[offset].to_int() - 48
      if code < 0 || code > 63 {
        raise InvalidInput("mask RLE counts invalid character at \{offset}")
      }
      if shift >= 35 {
        raise InvalidInput("mask RLE counts run too long at character \{start}")
      }
      value = value | ((code & 31).to_int64() << shift)
      shift += 5
      offset += 1
      if (code & 32) == 0 {
        if (code & 16) != 0 {
          value -= 1L << shift
        }
        break
      }
    }
    if counts.length() > 2 {
      value += counts[counts.length() - 2].to_int64()
    }
    if value < 0L || value > pixels - total {
      raise InvalidInput("mask RLE counts invalid run at character \{start}")
    }
    total += value
    counts.push(value.to_int())
  }
  CocoRle::new(height, width, counts)
}

///|
/// Exports the stored run sequence in COCO compressed counts format.
pub fn CocoRle::to_compressed(self : CocoRle) -> String {
  let encoded = StringBuilder()
  for index, count in self.counts {
    let mut value = count.to_int64()
    if index > 2 {
      value -= self.counts[index - 2].to_int64()
    }
    while true {
      let mut code = (value & 31L).to_int()
      value = value >> 5
      let more = if (code & 16) != 0 { value != -1L } else { value != 0L }
      if more {
        code = code | 32
      }
      encoded.write_char((code + 48).to_char().unwrap())
      if !more {
        break
      }
    }
  }
  encoded.to_string()
}

///|
fn rle_json_integer(value : Json, location : String) -> Int raise EvalError {
  match value {
    Number(number, ..) if finite(number) &&
      number >= 0.0 &&
      number <= 2147483647.0 &&
      number.trunc() == number => number.to_int()
    _ =>
      raise InvalidInput(location + " must be a nonnegative Int-sized integer")
  }
}

///|
/// Parses one COCO segmentation RLE object: size is [height, width] and counts
/// is either an integer run array or a compressed string. Polygons are rejected.
/// Size and array counts must decode to nonnegative Int-sized integer values.
pub fn parse_coco_rle(source : String) -> CocoRle raise EvalError {
  let value = @json.parse(source) catch {
    _ => raise InvalidInput("mask RLE is not valid JSON")
  }
  parse_rle_value(value)
}

///|
fn parse_rle_value(value : Json) -> CocoRle raise EvalError {
  guard value is Object(fields) else {
    raise InvalidInput("mask RLE must be an object with size and counts")
  }
  let size = match fields.get("size") {
    Some(Array(values)) if values.length() == 2 => values
    _ => raise InvalidInput("mask RLE size must be [height, width]")
  }
  let height = rle_json_integer(size[0], "mask RLE size[0]")
  let width = rle_json_integer(size[1], "mask RLE size[1]")
  // Validate dimensions before allocating or decoding counts.
  let _ = rle_pixel_count(height, width)
  match fields.get("counts") {
    Some(String(encoded)) => CocoRle::from_compressed(height, width, encoded)
    Some(Array(values)) => {
      let counts = []
      for index, value in values {
        counts.push(rle_json_integer(value, "mask RLE counts[\{index}]"))
      }
      CocoRle::new(height, width, counts)
    }
    _ =>
      raise InvalidInput(
        "mask RLE counts must be a run array or compressed string",
      )
  }
}
