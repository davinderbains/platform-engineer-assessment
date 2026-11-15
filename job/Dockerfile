FROM python:3.13.18-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY image_job.py .
USER 10001:10001
ENTRYPOINT ["python", "/app/image_job.py"]
