# Usage
```
./ec2-start.sh
or
./ec2-start.sh profile keyword
```

# Setting

alias 등록(ec2-start.sh 가 있는 곳에서)
```
alias ec2-start=`PWD`'/ec2-start.sh'
```

alias 삭제
```
unalias ec2-start
```

배포 : ec2-ssm
```
cp ec2-start.sh ec2-ssm
chmod +x ec2-ssm
mv ec2-ssm /usr/local/bin/ec2-ssm
```

# Prerequisite
### aws configure

~/.aws/config
```
cat << EOF > ~/.aws/config
[default]
region = ap-northeast-2
output = json
EOF
```

~/.aws/credentials
```
ACCESSKEY=
SECRETKEY=
ASSUME_ROLE=
USERID=

cat << EOF > ~/.aws/credentials
[default]
aws_access_key_id = $ACCESSKEY
aws_secret_access_key = $SECRETKEY

EOF
```
### Bash Version upgrade(4버전 이상이어야 함.)
확인 : bash -version 

MacOS
```
brew upgrade
brew install bash
```

### AWS CLI V2 설치(V2는 아니어도 되나 cli 프로그램은 있어야 함.)
참고: https://docs.aws.amazon.com/ko_kr/cli/latest/userguide/install-cliv2.html
https://docs.aws.amazon.com/ko_kr/cli/latest/userguide/getting-started-install.html

### AWS CLI용 Session Manager 플러그인 설치
참고: https://docs.aws.amazon.com/ko_kr/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

MacOS
```
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip" -o "sessionmanager-bundle.zip"
unzip sessionmanager-bundle.zip
sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin
```


ec2-ssm-policy 각 계정마다 정책 생성 \
description : ec2-role-@profile@
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "ec2:DescribeInstances",
            "Resource": "*"
        },
        {
            "Sid": "StartSessionAll",
            "Effect": "Allow",
            "Action": [
                "ssm:StartSession"
            ],
            "Resource": "arn:aws:ec2:ap-northeast-2:xxxxx:instance/*",
            "Condition": {
                "StringLike": {
                    "aws:PrincipalTag/Role": [
                        "Administrator",
                        "Manager"
                    ]
                }
            }
        },
        {
            "Sid": "StartSessionAllowByTag",
            "Effect": "Allow",
            "Action": "ssm:StartSession",
            "Resource": "arn:aws:ec2:ap-northeast-2:xxxxx:instance/*",
            "Condition": {
                "StringLike": {
                    "ssm:resourceTag/SessionAllow": [
                        "*${aws:PrincipalTag/Role}*",
                        "*${aws:username}*"
                    ]
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ssm:ResumeSession",
                "ssm:TerminateSession"
            ],
            "Resource": "arn:aws:ssm:*:*:session/${aws:username}-*"
        }
    ]
}
```

ec2-role-ssm attach ec2-ssm-policy
ec2-role-ssm trust relation policy, ip 제한을 여기에 두는게 좋을듯?
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::xxxxx:root"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "Bool": {
                    "aws:MultiFactorAuthPresent": "true"
                }
            }
        },
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::xxxxx:root"
            },
            "Action": "sts:TagSession"
        }
    ]
}
```
