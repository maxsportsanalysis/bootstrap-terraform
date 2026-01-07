# Bootstrap

Principal ⇒ trust policy (who is allowed to act as something)

Resource ⇒ permission policy (what this identity may act on)

## AWS Resource Naming Conventions

### IAM User Name Format

* [team].[firstname].[lastname].[environment] 
  * *e.g., devops.maxim.cilek.prod*
* [firstname].[lastname].[environment]
  * *e.g., maxim.cilek.prod*

### MFA Device Format

* [user-or-role-name]-[env]-virtual-mfa-[unique-id]
  * *e.g., john.doe-prod-virtual-mfa-01*
* [company]-[user-or-role]-[env]-virtual-mfa-[number]
  * *e.g., maxsportsanalysis-bootstrap-prod-virtual-mfa-1*


### IAM Role Name Format

* [company]-[project-or-service]-[env]-role-[purpose] 
  * *e.g., maxsportsanalysis-orders-prod-role-readonly*

### IAM Policy Name Format

* [company]-[project-or-service]-[env]-policy-[permission-scope]
  * *e.g., maxsapp-orders-prod-policy-s3-readonly*


## 1. Create User

```bash
aws iam create-user --user-name bootstrap
```

### User Resource

```json
{
  "User": {
    "Path": "/",
    "UserName": "bootstrap",
    "UserId": "*********************",
    "Arn": "arn:aws:iam::242201314218:user/bootstrap",
    "CreateDate": "2026-01-02T10:55:28+00:00"
  }
}
```

## 2. Virtual MFA Device (*optional*)

### MFA Bootstrap Device

* `--virtual-mfa-device-name`: The name of the virtual MFA device, which must be unique. Use with path to uniquely identify a virtual MFA device.

* `--bootstrap-method`: Method to use to seed the virtual MFA. Valid Values: QRCodePNG | Base32StringSeed

* `--outfile`: The path and file name where the bootstrap information will be stored.

  ```bash
  aws iam create-virtual-mfa-device \
  --virtual-mfa-device-name maxsportsanalysis-bootstrap-virtual-mfa \
  --bootstrap-method Base32StringSeed \
  --outfile ./maxsportsanalysis-bootstrap-virtual-mfa.txt
  ```

  #### MFA Device Resource

  ```json
  {
    "VirtualMFADevice": {
      "SerialNumber": "arn:aws:iam::[ACCOUNT_ID]:mfa/${virtual-mfa-device-name}"
    }
  }
  ```


### Enable Bootstrap User's MFA Device

#### Authentication Codes

**1.** Go through the QR Code website-based AWS console.

**2.** Copy the secret key manually into authentication app

```sh
cat ./maxsportsanalysis-bootstrap-virtual-mfa.txt; echo
```

**3.** Use `oauth` for programmatically getting the authentication codes (*root user still has to save it to an authenticator app*).

```sh
oathtool --base32 --totp "SECRET_KEY" -w 1
```

##### Programmatically (Not Very Secure)

```sh
mapfile -t codes < <(oathtool --base32 --totp "$(tr -d '\n' < ./maxsportsanalysis-bootstrap-virtual-mfa.txt)" -w 1)
```

#### AWS Command

**Note:** If manually retrieving authentication codes, replace variable references with the codes.

```sh
aws iam enable-mfa-device --user-name bootstrap \
  --serial-number arn:aws:iam::242201314218:mfa/maxsportsanalysis-bootstrap-virtual-mfa \
  --authentication-code1 ${codes[0]} \
  --authentication-code2 ${codes[1]}
```

#### MFA Device Resource

```json
{
  "SerialNumber": "arn:aws:iam::[ACCOUNT_ID]:mfa/${virtual-mfa-device-name}",
  "User": {
    "Path": "/",
    "UserName": "bootstrap",
    "UserId": "*********************",
    "Arn": "arn:aws:iam::[ACCOUNT_ID]:user/bootstrap",
    "CreateDate": "YYYY-MM-DDTHH:MM:SS+00:00"
  },
  "EnableDate": "YYYY-MM-DDTHH:MM:SS+00:00"
}
```

## 3. Create Bootstrap Role (Trust Policy)

This policy is used to answer "*Who do I trust to assume me?*". In this case, the only IAM user that should be allowed to assume the Bootstrap role is the Bootstrap user.


```sh
aws iam create-role \
--role-name Bootstrap \
--description "Bootstrap role for creating identity providers and IAM roles" \
--assume-role-policy-document file://<(cat <<EOF
{
  "Version":"2012-10-17",		 	 	 
  "Statement": [
      {
          "Effect": "Allow",
          "Principal": { "AWS": "arn:aws:iam::242201314218:user/bootstrap" },
          "Action": "sts:AssumeRole",
          "Condition": { "Bool": { "aws:MultiFactorAuthPresent": "true" } }
      }
  ]
}
EOF
)
```

## 4. Create Bootstrap Permissions Policy (Permission Policy)

**Note:** This policy is used to answer “*What actions can I perform, and on what?*”.


```sh
aws iam put-role-policy \
--role-name Bootstrap \
--policy-name BootstrapPermissions \
--policy-document file://<(cat <<EOF
{
  "Version":"2012-10-17",		 	 	 
  "Statement": [
      {
          "Sid": "CreateResourcePermissions",
          "Effect": "Allow",
          "Action": [
            "iam:CreateOpenIDConnectProvider",
            "iam:CreateRole",
            "iam:CreatePolicy"
          ],
          "Resource": "*"
      },
      {
          "Sid": "AttachResourcePermissions",
          "Effect": "Allow",
          "Action": [
            "iam:PutRolePolicy"
          ],
          "Resource": "arn:aws:iam::242201314218:role/Bootstrap"
      },
      {
          "Sid": "GetResourcePermissions",
          "Effect": "Allow",
          "Action": [
            "iam:GetOpenIDConnectProvider"
          ],
          "Resource": "arn:aws:iam::242201314218:oidc-provider/token.actions.githubusercontent.com"
      },
      {
          "Sid": "DeleteResourcePermissions",
          "Effect": "Allow",
          "Action": [
            "iam:DeleteOpenIDConnectProvider"
          ],
          "Resource": "arn:aws:iam::242201314218:oidc-provider/token.actions.githubusercontent.com"
      }
  ]
}
EOF
)
```

## 5. Allow Bootstrap User to Assume Role

Now, the bootstrap user needs to able to assume the role.

### Put User Policy on Bootstrap User
```sh
aws iam put-user-policy \
--user-name bootstrap \
--policy-name AssumeBootstrapRole \
--policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sts:AssumeRole",
    "Resource": "arn:aws:iam::242201314218:role/Bootstrap"
  }]
}'
```

## 6. Create Bootstrap User Access Key

Since it is not possible to AssumeRole as root, access key must be used for changing to Bootstrap user so the role can be assumed.

### AWS Command
```sh

# Default User
aws configure set profile.default.region us-east-2
aws configure set profile.default.output json

aws configure set profile.bootstrap.role_arn arn:aws:iam::242201314218:role/Bootstrap
aws configure set profile.bootstrap.source_profile bootstrap-user
aws configure set profile.bootstrap.mfa_serial arn:aws:iam::242201314218:mfa/maxsportsanalysis-bootstrap-virtual-mfa


aws iam create-access-key --user-name bootstrap --output json | jq -r '.AccessKey | "\(.AccessKeyId) \(.SecretAccessKey)"' | \
while read access_key secret_key; do
  aws configure set aws_access_key_id "${access_key}" --profile bootstrap-user
  aws configure set aws_secret_access_key "${secret_key}" --profile bootstrap-user
done
```

### Changing Session Credentials

#### Caller Identity Full

```sh
aws sts get-caller-identity
```
```json
{
    "UserId": "[IAM_USER_ID]",
    "Account": "[ACCOUNT_ID]",
    "Arn": "arn:aws:iam::[ACCOUNT_ID]:user/${iam_user}"
}
```

#### Caller Identity (IAM User Name)

```sh
aws sts get-caller-identity --query Arn --output text | awk -F'/' '{print $NF}'
```

#### Get Session Token as Bootstrap User

```sh
aws sts get-session-token \
--serial-number arn:aws:iam::242201314218:mfa/maxsportsanalysis-bootstrap-virtual-mfa \
--token-code "${mfa_code}" \
--duration-seconds 900 \
--output json | jq -r '.Credentials | "\(.AccessKeyId) \(.SecretAccessKey) \(.SessionToken)"' | \
while read access_key secret_key session_token; do
  aws configure set aws_access_key_id "${access_key}" --profile bootstrap
  aws configure set aws_secret_access_key "${secret_key}" --profile bootstrap
  aws configure set aws_session_token "${session_token}" --profile bootstrap
done
```

#### Verify User Change

```sh
aws sts get-caller-identity --query Arn --output text | awk -F'/' '{print $NF}'
```
```
bootstrap
```


## 7. Assume Bootstrap Role

```sh
aws sts assume-role \
--profile bootstrap \
--role-session-name "bootstrap-$(date +%s)" \
--role-arn arn:aws:iam::242201314218:role/Bootstrap \
--serial-number arn:aws:iam::242201314218:mfa/maxsportsanalysis-bootstrap-virtual-mfa \
--token-code "${code}" \
--output json | jq -r '.Credentials | "\(.AccessKeyId) \(.SecretAccessKey) \(.SessionToken)"' | \
while read access_key secret_key session_token; do
  aws configure set aws_access_key_id "${access_key}" --profile bootstrap
  aws configure set aws_secret_access_key "${secret_key}" --profile bootstrap
  aws configure set aws_session_token "${session_token}" --profile bootstrap
done
```

```json
{
    "Credentials": {
        "AccessKeyId": "********************",
        "SecretAccessKey": "****************************************",
        "SessionToken": "**************.......*****************************",
        "Expiration": "YYYY-MM-DDTHH:MM:SS+00:00"
    },
    "AssumedRoleUser": {
        "AssumedRoleId": "[USER_ID]:${role-session-name}",
        "Arn": "arn:aws:sts::[ACCOUNT_ID]:assumed-role/Bootstrap/${role-session-name}"
    }
}
```

### Verify Caller Identity

```sh
aws sts get-caller-identity --query Arn --output text | awk -F'/' '{print $NF}'
```

## 8. Create GitHub OIDC Provider

```sh
aws iam create-open-id-connect-provider \
--url "https://token.actions.githubusercontent.com" \
--thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
--client-id-list "sts.amazonaws.com"
```














### NOTES


This means Bootstrap role can only put inline policies on itself.

```json
{
    "Sid": "Attach Resource Permissions",
    "Effect": "Allow",
    "Action": [
      "iam:PutRolePolicy"
    ],
    "Resource": "arn:aws:iam::242201314218:role/Bootstrap"
}
```

* Bootstrap needs to create the GitHub OIDC provider, github actions role, 


















#### END


aws iam create-access-key --user-name bootstrap
```json
  {
    "AccessKey": {
      "UserName": "bootstrap",
      "AccessKeyId": "********************",
      "Status": "Active",
      "SecretAccessKey": "****************************************",
      "CreateDate": "YYYY-MM-DDTHH:MM:SS+00:00"
    }
  }
```

## GITHUB OIDC PROVIDER

Create Provider: `aws iam create-open-id-connect-provider --url "https://token.actions.githubusercontent.com" --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" --client-id-list "sts.amazonaws.com"`

`{"OpenIDConnectProviderArn": "arn:aws:iam::242201314218:oidc-provider/token.actions.githubusercontent.com"}`




aws iam create-role --role-name GithubOIDCProviderRole --assume-role-policy-document file://<(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::242201314218:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": [
            "repo:maxsportsanalysis/bootstrap-terraform:ref:refs/heads/main",
            "repo:maxsportsanalysis/infra-terraform:ref:refs/heads/main"
          ]
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::242201314218:user/bootstrap"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

aws iam create-policy --policy-name GithubOIDCProviderPolicy --policy-document file://<(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "iam:PassRole",
        "iam:CreateRole"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)