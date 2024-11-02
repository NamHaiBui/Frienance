FROM python:3.10.4
RUN apt-get update && apt-get install -y tesseract-ocr-all imagemagick ffmpeg libsm6 libxext6
RUN pip install poetry
ADD pyproject.toml poetry.lock /code/

WORKDIR /app
COPY . .

RUN mkdir -p /app/data/img
RUN mkdir -p /app/data/tmp
RUN mkdir -p /app/data/txt

RUN poetry config virtualenvs.create false && poetry config installer.max-workers 10
RUN poetry install

CMD ["make", "run"]
