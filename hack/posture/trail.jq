# What a role's credentials did, from CloudTrail's management events: refused calls are something
# on the machine asking for more than it is given, and a call from an address that is not one of
# the installation's ($ips) is the credentials used off the machine. Input: cloudtrail lookup-events.
.Events[].CloudTrailEvent
| fromjson
| (
    (if ((.errorCode // "") | test("AccessDenied|Unauthorized")) then
      "\(.eventSource) \(.eventName) was refused (\(.errorCode)): something on the machine asked for more than its role gives"
    else empty end),
    (.sourceIPAddress as $s
     | if ($ips | index($s)) or $s == "AWS Internal" or ($s | endswith(".amazonaws.com")) then empty
       else "\(.eventSource) \(.eventName) from \($s), none of the installation's addresses: the role's credentials were used off its machines" end)
  )
