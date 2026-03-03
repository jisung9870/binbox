FROM python:3.13-slim

ENV ANSIBLE_CORE_VERSION=2.20.3 \
    ANSIBLE_VERSION=11.4.0 \
    ANSIBLE_LINT=25.4.0

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      sshpass git openssh-client && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
      ansible-core==${ANSIBLE_CORE_VERSION} \
      ansible==${ANSIBLE_VERSION} \
      ansible-lint==${ANSIBLE_LINT} \
      mitogen jmespath

RUN mkdir -p /etc/ansible && \
    echo 'localhost' > /etc/ansible/hosts

WORKDIR /ansible
CMD ["ansible-playbook", "--version"]
