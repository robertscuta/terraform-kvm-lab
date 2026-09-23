network:
  version: 2
  ethernets:
    all-eth:
      match:
        name: "en*"
      addresses: [${ip}/24]
      routes:
        - to: default
          via: 192.168.XX.XX    # Your gateway IP
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]