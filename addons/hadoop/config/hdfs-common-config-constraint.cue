package kubeblocks

import "strings"

#HDFSCommonParameter: {
    fsDefaultFS?: string
    ioFileBufferSize?: int
    ioBytesPerChecksum?: int
    ipcClientConnectTimeout?: int
    ipcClientConnectMaxRetries?: int
    ipcClientConnectRetryInterval?: int
    ipcServerListenQueueSize?: int
    hadoopSecurityAuthorization?: bool
}

parameter: [string]: {
    value: string
    description?: string
    type:       "string" | "int" | "bool"
    mutable?:   bool
}

parameter: {
    "fs.defaultFS": {
        value:       #HDFSCommonParameter.fsDefaultFS
        description: "The name of the default file system. A URI whose scheme and authority determine the FileSystem implementation."
        type:        "string"
        mutable:     false
    }
    "io.file.buffer.size": {
        value:       "\( #HDFSCommonParameter.ioFileBufferSize )"
        description: "The size of buffer for use in sequence files, RPC, etc."
        type:        "int"
        mutable:     true
    }
    "io.bytes.per.checksum": {
        value:       "\( #HDFSCommonParameter.ioBytesPerChecksum )"
        description: "The number of bytes per checksum. Must be less than or equal to io.file.buffer.size."
        type:        "int"
        mutable:     false
    }
    "ipc.client.connect.timeout": {
        value:       "\( #HDFSCommonParameter.ipcClientConnectTimeout )"
        description: "The socket connect timeout in milliseconds."
        type:        "int"
        mutable:     true
    }
    "ipc.client.connect.max.retries": {
        value:       "\( #HDFSCommonParameter.ipcClientConnectMaxRetries )"
        description: "The number of retries for socket connections."
        type:        "int"
        mutable:     true
    }
    "ipc.client.connect.retry.interval": {
        value:       "\( #HDFSCommonParameter.ipcClientConnectRetryInterval )"
        description: "The retry interval in milliseconds for socket connections."
        type:        "int"
        mutable:     true
    }
    "ipc.server.listen.queue.size": {
        value:       "\( #HDFSCommonParameter.ipcServerListenQueueSize )"
        description: "The maximum backlog of TCP connections."
        type:        "int"
        mutable:     true
    }
    "hadoop.security.authorization": {
        value:       strings.ToLower("\( #HDFSCommonParameter.hadoopSecurityAuthorization )")
        description: "Enable service-level authorization checks."
        type:        "bool"
        mutable:     false
    }
}
