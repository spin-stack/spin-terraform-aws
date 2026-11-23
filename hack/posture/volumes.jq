# Every volume attached to the run's instances is encrypted under the installation's own key, $key
# (modules/controlplane/disks.tf). Input: ec2 describe-volumes.
.Volumes[]
| if .Encrypted != true then "\(.VolumeId) on \(.Attachments[0].InstanceId // "no instance"): not encrypted"
  elif .KmsKeyId != $key then "\(.VolumeId) on \(.Attachments[0].InstanceId // "no instance"): encrypted under \(.KmsKeyId), not the installation's key"
  else empty end
