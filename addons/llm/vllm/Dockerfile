FROM nvcr.io/nvidia/pytorch:22.12-py3

RUN pip uninstall -y torch
COPY ./vllm ./vllm
RUN pip install -e ./vllm
RUN pip install typing_extensions==4.5.0 pydantic==1.10.0

CMD ["python", "./vllm/vllm/entrypoints/api_server.py"]