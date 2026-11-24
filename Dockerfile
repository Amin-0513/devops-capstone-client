FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1

ARG APP_VERSION=local
ARG BUILD_TIME="not built by CI"
ENV APP_VERSION=$APP_VERSION
ENV BUILD_TIME=$BUILD_TIME

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Volume mount point
RUN mkdir -p /clientdata
VOLUME ["/clientdata"]

# Streamlit default port
EXPOSE 8501

CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0", "--browser.gatherUsageStats=false"]