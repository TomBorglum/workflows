The docker-hub-publish workflow fails at present due to this 

 INFO: Downloading bootstrap version 'v3.0.6' of cosign to verify version to be installed...
        https://github.com/sigstore/cosign/releases/download/v3.0.6/cosign-linux-amd64
  curl: (22) The requested URL returned error: 504
  curl: (22) The requested URL returned error: 504
  curl: (22) The requested URL returned error: 504
  curl: (22) The requested URL returned error: 504
  Error: Process completed with exit code 22.

  Errors like these are intermittent but still disruptive - and I see these happening more often that I would like.

  I would like to take this opportunity to harden the workflow such that it does not download this asset on every run but instead caches it - and only if the specified version does not exist in the cache then go ahead and download the asset.

  Does this make sense - and is this a best practice strategy for handling issues like this?