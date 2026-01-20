/// Fuzzy matching utilities for receipt parsing.
/// 
/// This library provides a comprehensive fuzzy matching system for extracting
/// structured data from receipt text, including store names, dates, totals,
/// and line items.
/// 
/// ## Main Components
/// 
/// - **Core**: String utilities and config management
/// - **Extractors**: Market, date, sum, and item extraction
/// - **Learning**: Pattern learning from user confirmations
/// - **Store**: Store/restaurant CRUD and categorization
/// - **Constants**: Regex patterns and presets
/// - **Models**: Data structures for extraction results
/// 
/// ```
library;
export 'constants/constants.dart';
export 'core/core.dart';
export 'extractors/extractors.dart';
export 'learning/learning.dart';
export 'model/model.dart';
export 'store/store.dart';
