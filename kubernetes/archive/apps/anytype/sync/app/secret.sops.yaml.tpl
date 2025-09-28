apiVersion: v1
kind: Secret
metadata:
  name: anytype-sync-secret
stringData:
  CONSENSUSNODE_PEER_ID: ${CONSENSUSNODE_PEER_ID}
  CONSENSUSNODE_PEER_KEY: ${CONSENSUSNODE_PEER_KEY}
  CONSENSUSNODE_SIGNING_KEY: ${CONSENSUSNODE_SIGNING_KEY}
  COORDINATOR_PEER_ID: ${COORDINATOR_PEER_ID}
  COORDINATOR_PEER_KEY: ${COORDINATOR_PEER_KEY}
  COORDINATOR_SIGNING_KEY: ${COORDINATOR_SIGNING_KEY}
  FILENODE_PEER_ID: ${FILENODE_PEER_ID}
  FILENODE_PEER_KEY: ${FILENODE_PEER_KEY}
  FILENODE_SIGNING_KEY: ${FILENODE_SIGNING_KEY}
  NODE1_PEER_ID: ${NODE1_PEER_ID}
  NODE1_PEER_KEY: ${NODE1_PEER_KEY}
  NODE1_SIGNING_KEY: ${NODE1_SIGNING_KEY}
  NETWORK: ${NETWORK}
  NETWORK_ID: ${NETWORK_ID}
---
apiVersion: v1
kind: Secret
metadata:
  name: anytype-sync-config-secret
stringData:
  any-sync-consensusnode.yaml: |
    account:
        peerId: ${CONSENSUSNODE_PEER_ID}
        peerKey: ${CONSENSUSNODE_PEER_KEY}
        signingKey: ${CONSENSUSNODE_SIGNING_KEY}
    drpc:
        stream:
            maxMsgSizeMb: 256
    yamux:
        listenAddrs:
            - 0.0.0.0:4530
        writeTimeoutSec: 10
        dialTimeoutSec: 10
    quic:
        listenAddrs:
            - 0.0.0.0:5530
        writeTimeoutSec: 10
        dialTimeoutSec: 10
    network:
        id: ${NETWORK}
        networkId: ${NETWORK_ID}
        nodes:
            - peerId: ${COORDINATOR_PEER_ID}
            addresses:
                - any-sync-coordinator:4830
                - quic://any-sync-coordinator:5830
                - anysync.${SECRET_DOMAIN}:4830
                - quic://anysync.${SECRET_DOMAIN}:5830
            types:
                - coordinator
            - peerId: ${CONSENSUSNODE_PEER_ID}
            addresses:
                - any-sync-consensusnode:4530
                - quic://any-sync-consensusnode:5530
                - anysync.${SECRET_DOMAIN}:4530
                - quic://anysync.${SECRET_DOMAIN}:5530
            types:
                - consensus
            - peerId: ${NODE1_PEER_ID}
            addresses:
                - any-sync-node-1:4430
                - quic://any-sync-node-1:5430
                - anysync.${SECRET_DOMAIN}:4430
                - quic://anysync.${SECRET_DOMAIN}:5430
            types:
                - tree
            - peerId: ${FILENODE_PEER_ID}
            addresses:
                - any-sync-filenode:4730
                - quic://any-sync-filenode:5730
                - anysync.${SECRET_DOMAIN}:4730
                - quic://anysync.${SECRET_DOMAIN}:5730
            types:
                - file
    networkStorePath: /networkStore
    log:
        production: false
        defaultLevel: ""
        namedLevels: {}
    metric:
        addr: 0.0.0.0:8000
    mongo:
        connect: mongodb://any-sync-mongodb-0.any-sync-mongodb-headless:27017/?w=majority
        database: consensus
        logCollection: log
  any-sync-coordinator.yaml: |
    account:
        peerId: ${COORDINATOR_PEER_ID}
        peerKey: ${COORDINATOR_PEER_KEY}
        signingKey: ${COORDINATOR_SIGNING_KEY}
    drpc:
        stream:
            maxMsgSizeMb: 256
    yamux:
        listenAddrs:
            - 0.0.0.0:4830
        writeTimeoutSec: 10
        dialTimeoutSec: 10
    quic:
        listenAddrs:
            - 0.0.0.0:5830
        writeTimeoutSec: 10
        dialTimeoutSec: 10
    network:
        id: ${NETWORK}
        networkId: ${NETWORK_ID}
        nodes:
            - peerId: ${COORDINATOR_PEER_ID}
            addresses:
                - any-sync-coordinator:4830
                - quic://any-sync-coordinator:5830
                - anysync.${SECRET_DOMAIN}:4830
                - quic://anysync.${SECRET_DOMAIN}:5830
            types:
                - coordinator
            - peerId: ${CONSENSUSNODE_PEER_ID}
            addresses:
                - any-sync-consensusnode:4530
                - quic://any-sync-consensusnode:5530
                - anysync.${SECRET_DOMAIN}:4530
                - quic://anysync.${SECRET_DOMAIN}:5530
            types:
                - consensus
            - peerId: ${NODE1_PEER_ID}
            addresses:
                - any-sync-node-1:4430
                - quic://any-sync-node-1:5430
                - anysync.${SECRET_DOMAIN}:4430
                - quic://anysync.${SECRET_DOMAIN}:5430
            types:
                - tree
            - peerId: ${FILENODE_PEER_ID}
            addresses:
                - any-sync-filenode:4730
                - quic://any-sync-filenode:5730
                - anysync.${SECRET_DOMAIN}:4730
                - quic://anysync.${SECRET_DOMAIN}:5730
    networkStorePath: /networkStore
    log:
        production: false
        defaultLevel: ""
        namedLevels: {}
    metric:
        addr: 0.0.0.0:8000
    mongo:
        connect: mongodb://any-sync-mongodb-0.any-sync-mongodb-headless:27017/?w=majority
        database: coordinator
        log: log
        spaces: spaces
    spaceStatus:
        runSeconds: 5
        deletionPeriodDays: 0
    defaultLimits:
        spaceMembersRead: 1000
        spaceMembersWrite: 1000
        sharedSpacesLimit: 1000
  any-sync-filenode.yaml: |
    account:
        peerId: ${FILENODE_PEER_ID}
        peerKey: ${FILENODE_PEER_KEY}
        signingKey: ${FILENODE_SIGNING_KEY}
    drpc:
        stream:
            maxMsgSizeMb: 256
    yamux:
        listenAddrs:
            - 0.0.0.0:4730
        writeTimeoutSec: 10
        dialTimeoutSec: 10
    quic:
        listenAddrs:
            - 0.0.0.0:5730
        writeTimeoutSec: 10
        dialTimeoutSec: 10
    network:
        id: ${NETWORK}
        networkId: ${NETWORK_ID}
        nodes:
            - peerId: ${COORDINATOR_PEER_ID}
            addresses:
                - any-sync-coordinator:4830
                - quic://any-sync-coordinator:5830
                - anysync.${SECRET_DOMAIN}:4830
                - quic://anysync.${SECRET_DOMAIN}:5830
            types:
                - coordinator
            - peerId: ${CONSENSUSNODE_PEER_ID}
            addresses:
                - any-sync-consensusnode:4530
                - quic://any-sync-consensusnode:5530
                - anysync.${SECRET_DOMAIN}:4530
                - quic://anysync.${SECRET_DOMAIN}:5530
            types:
                - consensus
            - peerId: ${NODE1_PEER_ID}
            addresses:
                - any-sync-node-1:4430
                - quic://any-sync-node-1:5430
                - anysync.${SECRET_DOMAIN}:4430
                - quic://anysync.${SECRET_DOMAIN}:5430
            types:
                - tree
            - peerId: ${FILENODE_PEER_ID}
            addresses:
                - any-sync-filenode:4730
                - quic://any-sync-filenode:5730
                - anysync.${SECRET_DOMAIN}:4730
                - quic://anysync.${SECRET_DOMAIN}:5730
    networkStorePath: /networkStore
    log:
        production: false
        defaultLevel: ""
        namedLevels: {}
    metric:
        addr: 0.0.0.0:8000
    defaultLimit: 1099511627776
    s3Store:
        endpoint: http://rook-ceph-rgw-rook-ceph-object-store
        bucket: anytype-sync-bucket
        indexBucket: anytype-sync-bucket
        region: us-east-1
        profile: default
        maxThreads: 16
        forcePathStyle: true
    redis:
        isCluster: false
        url: redis://any-sync-redis:6379?dial_timeout=3&read_timeout=6s
  any-sync-node-1.yaml: |
    account:
        peerId: ${NODE1_PEER_ID}
        peerKey: ${NODE1_PEER_KEY}
        signingKey: ${NODE1_SIGNING_KEY}
    drpc:
        stream:
            maxMsgSizeMb: 256
    yamux:
        listenAddrs:
            - 0.0.0.0:4430
        writeTimeoutSec: 10
        dialTimeoutSec: 10
    quic:
        listenAddrs:
            - 0.0.0.0:5430
        writeTimeoutSec: 10
        dialTimeoutSec: 10
    network:
        id: ${NETWORK}
        networkId: ${NETWORK_ID}
        nodes:
            - peerId: ${COORDINATOR_PEER_ID}
            addresses:
                - any-sync-coordinator:4830
                - quic://any-sync-coordinator:5830
                - anysync.${SECRET_DOMAIN}:4830
                - quic://anysync.${SECRET_DOMAIN}:5830
            types:
                - coordinator
            - peerId: ${CONSENSUSNODE_PEER_ID}
            addresses:
                - any-sync-consensusnode:4530
                - quic://any-sync-consensusnode:5530
                - anysync.${SECRET_DOMAIN}:4530
                - quic://anysync.${SECRET_DOMAIN}:5530
            types:
                - consensus
            - peerId: ${NODE1_PEER_ID}
            addresses:
                - any-sync-node-1:4430
                - quic://any-sync-node-1:5430
                - anysync.${SECRET_DOMAIN}:4430
                - quic://anysync.${SECRET_DOMAIN}:5430
            types:
                - tree
            - peerId: ${FILENODE_PEER_ID}
            addresses:
                - any-sync-filenode:4730
                - quic://any-sync-filenode:5730
                - anysync.${SECRET_DOMAIN}:4730
                - quic://anysync.${SECRET_DOMAIN}:5730
    networkStorePath: /networkStore
    log:
        production: false
        defaultLevel: ""
        namedLevels: {}
    metric:
        addr: 0.0.0.0:8000
    space:
        gcTTL: 60
        syncPeriod: 600
    storage:
        path: /storage
    nodeSync:
        syncOnStart: true
        periodicSyncHours: 2
    apiServer:
        listenAddr: 0.0.0.0:8080
  network.yaml: |
    id: ${NETWORK}
    networkId: ${NETWORK_ID}
    nodes:
        - peerId: ${COORDINATOR_PEER_ID}
        addresses:
            - any-sync-coordinator:4830
            - quic://any-sync-coordinator:5830
            - anysync.${SECRET_DOMAIN}:4830
            - quic://anysync.${SECRET_DOMAIN}:5830
        types:
            - coordinator
        - peerId: ${CONSENSUSNODE_PEER_ID}
        addresses:
            - any-sync-consensusnode:4530
            - quic://any-sync-consensusnode:5530
            - anysync.${SECRET_DOMAIN}:4530
            - quic://anysync.${SECRET_DOMAIN}:5530
        types:
            - consensus
        - peerId: ${NODE1_PEER_ID}
        addresses:
            - any-sync-node-1:4430
            - quic://any-sync-node-1:5430
            - anysync.${SECRET_DOMAIN}:4430
            - quic://anysync.${SECRET_DOMAIN}:5430
        types:
            - tree
        - peerId: ${FILENODE_PEER_ID}
        addresses:
            - any-sync-filenode:4730
            - quic://any-sync-filenode:5730
            - anysync.${SECRET_DOMAIN}:4730
            - quic://anysync.${SECRET_DOMAIN}:5730
  s3.conf: |
    [default]
    aws_access_key_id=${AWS_ACCESS_KEY_ID}
    aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
