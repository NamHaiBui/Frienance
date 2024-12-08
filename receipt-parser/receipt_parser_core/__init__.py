from .config import read_config
from .parse import *
from pytesseract import pytesseract


def main():
    pytesseract.tesseract_cmd = "C:/DEV/Tesseract-OCR/tesseract.exe"
    config = read_config()
    receipt_files = get_files_in_folder(config.receipts_path)
    stats = ocr_receipts(config, receipt_files)
    output_statistics(stats)
