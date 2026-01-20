enum FuzzyMatchingConfidence {
  high(0.85),
  medium(0.65),
  low(0.45);

  final double value;
  const FuzzyMatchingConfidence(this.value);
}