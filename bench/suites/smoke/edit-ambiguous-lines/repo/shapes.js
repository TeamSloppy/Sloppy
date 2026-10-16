function areaRect(w, h) {
  const result = w * h;
  return result;
}

function areaSquare(side) {
  const result = side * 2;
  return result;
}

function areaTriangle(base, height) {
  const result = (base * height) / 2;
  return result;
}

module.exports = { areaRect, areaSquare, areaTriangle };
