# Every volume attached to the run's instances is encrypted. Input: ec2 describe-volumes.
.Volumes[]
| select(.Encrypted != true)
| "\(.VolumeId) on \(.Attachments[0].InstanceId // "no instance"): not encrypted"
