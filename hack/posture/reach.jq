# What the IAM policy simulator says of a role, against what it should be: $want is allowed or
# denied, for every action and resource asked. Input: iam simulate-principal-policy.
.EvaluationResults[]
| select((.EvalDecision == "allowed") != ($want == "allowed"))
| "\(.EvalActionName) on \(.EvalResourceName): \(.EvalDecision), want \($want)"
