/// Service layer exports for Frienance.
/// 
/// Provides:
/// - Abstract Service base class with semaphore concurrency control
/// - ReceiptParserService for full receipt processing pipeline
/// - LLMInterpreterService for Gemini-based advanced processing
library;

// Core service infrastructure
export 'service.dart';

// Concrete service implementations
export 'package:frienance/services/receipt_parser_service.dart';
export 'package:frienance/services/llm_interpreter_service.dart';
