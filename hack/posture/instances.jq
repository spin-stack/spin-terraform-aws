# What each instance the run made says of itself, against what its launch template promised: one
# line per broken promise, nothing when every instance keeps them. Input: ec2 describe-instances.
.Reservations[].Instances[]
| .InstanceId as $id
| .MetadataOptions as $m
| (
    (if $m.HttpTokens != "required" then "the metadata service answers IMDSv1 (HttpTokens=\($m.HttpTokens))" else empty end),
    (if $m.HttpPutResponseHopLimit != 1 then "the metadata service answers \($m.HttpPutResponseHopLimit) hops away: a guest's or a container's packets reach the role" else empty end),
    (if $m.HttpProtocolIpv6 != "disabled" then "the metadata service answers on IPv6 (HttpProtocolIpv6=\($m.HttpProtocolIpv6)), an address no rule of spin's names" else empty end),
    (if $m.InstanceMetadataTags != "disabled" then "the metadata service says the instance's tags (InstanceMetadataTags=\($m.InstanceMetadataTags))" else empty end),
    (if (.CurrentInstanceBootMode // .BootMode) != "uefi" then "boot mode \(.CurrentInstanceBootMode // .BootMode), not uefi: nothing it booted was measured" else empty end)
  )
| "\($id): \(.)"
