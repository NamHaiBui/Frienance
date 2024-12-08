class Receipt {
  String market;
  String date;
  List<String> items;
  double total;

  Receipt({
    required this.market,
    required this.date,
    required this.items,
    required this.total,
  });

  // Method to parse OCR text into a Receipt object
  factory Receipt.fromOCR(String ocrText) {
    // ...existing code...
    return Receipt(
      market: '', // Extracted market name
      date: '',   // Extracted date
      items: [],  // Extracted list of items
      total: 0.0, // Extracted total amount
    );
  }
}
