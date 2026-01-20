class FuzzyMatchRegexPatterns{

  // Regex pattern collections for different extraction types
  static final List<RegExp> datePatterns = [
    RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b'), // MM/DD/YYYY, DD-MM-YY
    RegExp(r'\b(\d{2,4})[/\-.](\d{1,2})[/\-.](\d{1,2})\b'), // YYYY-MM-DD
    RegExp(r'\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\w*\s+(\d{2,4})\b', caseSensitive: false),
    RegExp(r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\w*\s+(\d{1,2}),?\s+(\d{2,4})\b', caseSensitive: false),
    RegExp(r'\b(\d{1,2})\s*/\s*(\d{1,2})\s*/\s*(\d{2,4})\b'), // With spaces around slashes
  ];

  static final List<RegExp> sumPatterns = [
    RegExp(r'(?:total|sum|amount|due|balance)[:\s]*[\$]?\s*(\d+[.,]\d{2})\b', caseSensitive: false),
    RegExp(r'[\$]\s*(\d+[.,]\d{2})\b'),
    RegExp(r'\b(\d+[.,]\d{2})\s*(?:total|sum|amount|due)\b', caseSensitive: false),
    RegExp(r'(?:grand\s*total|net\s*total)[:\s]*[\$]?\s*(\d+[.,]\d{2})\b', caseSensitive: false),
    RegExp(r'\btotal\s*-?>?\s*[\$]?\s*(\d+[.,]\d{2})\b', caseSensitive: false),
  ];

  static final List<RegExp> itemPatterns = [
    // Pattern: ITEM_NAME -> PRICE or ITEM_NAME PRICE (optional trailing char)
    RegExp(r'^(.+?)\s*-?>\s*(\d+[.,]\d{2})\s*[A-Z]?'),
    // Pattern: QTY x ITEM_NAME PRICE
    RegExp(r'(\d+)\s*[x@]\s*(.+?)\s+(\d+[.,]\d{2})'),
    // Pattern: ITEM_NAME CODE PRICE
    RegExp(r'^([A-Za-z\s]+)\s+\d+\s+(\d+[.,]\d{2})'),
    // Pattern: ITEM_NAME $PRICE
    RegExp(r'^(.+?)\s+\$(\d+[.,]\d{2})'),
    // Pattern with product codes
    RegExp(r'^([A-Za-z][A-Za-z\s]+)\s+\d{6,}\s+(\d+[.,]\d{2})'),
  ];

  static final List<String> marketIndicators = [
    'walmart', 'target', 'costco', 'kroger', 'safeway', 'whole foods',
    'trader joe', 'aldi', 'publix', 'winco', 'spar', 'metro', 'lidl',
    'meijer', 'heb', 'food lion', 'giant', 'stop & shop', 'wegmans',
    'sprouts', 'fresh market', 'market basket', 'piggly wiggly',
  ];
  const FuzzyMatchRegexPatterns._();
}