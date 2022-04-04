#!/usr/bin/env bash
# bash -version 4버전 이후부터 실행 가능.

function select_option {

    # little helpers for terminal print control and key input
    ESC=$( printf "\033")
    cursor_blink_on()  { printf "$ESC[?25h"; }
    cursor_blink_off() { printf "$ESC[?25l"; }
    cursor_to()        { printf "$ESC[$1;${2:-1}H"; }
    print_option()     { printf "   $1 "; }
    print_selected()   { printf "> $ESC[7m $1 $ESC[27m"; }
    get_cursor_row()   { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; }
    key_input()        { read -s -n3 key 2>/dev/null >&2
                         if [[ $key = $ESC[A ]]; then echo up;    fi
                         if [[ $key = $ESC[B ]]; then echo down;  fi
                         if [[ $key = ""     ]]; then echo enter; fi; }

    # initially print empty new lines (scroll down if at bottom of screen)
    for opt; do printf "\n"; done

    # determine current screen position for overwriting the options
    local lastrow=`get_cursor_row`
    local startrow=$(($lastrow - $#))

    # ensure cursor and input echoing back on upon a ctrl+c during read -s
    trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
    cursor_blink_off

    local selected=0
    while true; do
        # print options by overwriting the last lines
        local idx=0
        for opt; do
            cursor_to $(($startrow + $idx))
            if [ $idx -eq $selected ]; then
                print_selected "$opt"
            else
                print_option "$opt"
            fi
            ((idx++))
        done

        # user key control
        case `key_input` in
            enter) break;;
            up)    ((selected--));
                   if [ $selected -lt 0 ]; then selected=$(($# - 1)); fi;;
            down)  ((selected++));
                   if [ $selected -ge $# ]; then selected=0; fi;;
        esac
    done

    # cursor position back to normal
    cursor_to $lastrow
    printf "\n"
    cursor_blink_on

    return $selected
}

##############################################################
##############################################################

# IAM User Data 불러오기
# 참고로 query에서 나오는 순서는 알파벳 순이다(A-Z, a-z)
# 아래와 같이 나열한 순서로 나오지 않고, 혼란스러울 것 같아서 결과를 보고 순서를 맞춰나열한 것 뿐이다.
# IAM_PROFILE : iam 사용자의 profile env에 IAM_PROFILE이 있다면 env에 세팅되어 있는 값을 사용하자. 없다면 default로 세팅
if [ "$IAM_PROFILE" = "" ]; then
    IAM_PROFILE="default"
fi
UserInfo=$(aws iam get-user \
--query "User.{
            Email:Tags[?Key=='Email']|[0].Value,
            Name:Tags[?Key=='Name']|[0].Value,
            Profile:Tags[?Key=='SsmProfile']|[0].Value,
            Role:Tags[?Key=='Role']|[0].Value,
            User:UserName
        }"  \
--profile ${IAM_PROFILE} --output text)

if [ -z "${UserInfo}" ]; then
    echo "IAM get-user Fail !!! Who are You ???"
fi

KEYWORD=$1
PROFILE=$2 # PROFILE은 받은 인자 값이 있다면 받은 걸로 지정

EMAIL=$(echo "${UserInfo}" | cut -f1) 
NAME=$(echo "${UserInfo}" | cut -f2) 

# $UserInfo | cut -f3 에 대한 처리
# 2번째 arg 에 값이 없다면 IAM User의 SsmProfile TAG Value 불러오기(Default Profile 이라고 보면 됨.)
if [ "$PROFILE" = "" ]; then
    PROFILE=$(echo "${UserInfo}" | cut -f3) 
    # 해당 TAG가 없다면 PROFILE을 입력받도록 유도.
    if [ "$PROFILE" = "None" ]; then
        read -p 'Enter your profile: ' PROFILE
    fi
fi

ROLE=$(echo "${UserInfo}" | cut -f4) 
USERNAME=$(echo "${UserInfo}" | cut -f5) 

REGION="ap-northeast-2"

# Welcome Message
echo "Hello !! ${NAME}(${EMAIL})"
echo "Welcome to EC2 SSM !!!"
echo "Your IAM profile is ${IAM_PROFILE}"
echo "Your Role profile is ${PROFILE}."

# $1 KEYWORD 입력 받은게 없다면 입력받기
if [ "$KEYWORD" = "" ]; then
    read -p 'Enter ec2 name keyword: ' KEYWORD
fi

# young-ssm y young
# work-dev-ssm wd work-dev 
# work-prd-ssm wp work-prd

declare -A profile_alias
profile_alias["y"]="young-ssm"
profile_alias["young"]="young-ssm"
profile_alias["young-ssm"]="mng-ssm"
profile_alias["wd"]="work-dev-ssm"
profile_alias["work-dev"]="work-dev-ssm"
profile_alias["work-dev-ssm"]="work-dev-ssm"
profile_alias["wp"]="work-prd-ssm"
profile_alias["work-prd"]="work-prd-ssm"
profile_alias["work-prd-ssm"]="work-prd-ssm"

if [[ "${profile_alias[${PROFILE}]}" == "" ]]; then
    echo "This Profile is not Matching !!! (${PROFILE})"
    exit 0
fi

PROFILE=${profile_alias[${PROFILE}]}
echo "Your profile full name is ${PROFILE}"

# PROFILE Define
# profile       account         account-number
# young-ssm     young713        xxxxxxxxxxxx
# work-ssm-prd  young-work      xxxxxxxxxxxx
# work-ssm-dev  young-work      xxxxxxxxxxxx
declare -A EC2_SSM_PROFILE_INFO
EC2_SSM_PROFILE_INFO["young-ssm"]="refine-mng:xxxxxxxxxxxx"
EC2_SSM_PROFILE_INFO["work-prd-ssm"]="refine-work:xxxxxxxxxxxx"
EC2_SSM_PROFILE_INFO["work-dev-ssm"]="refine-work:xxxxxxxxxxxx"

echo ${EC2_SSM_PROFILE_INFO[${PROFILE}]}
ACCOUNT=$(echo ${EC2_SSM_PROFILE_INFO[${PROFILE}]} | cut -f2 -d ":")

# role name define : ec2-role-${PROFILE} -> IAM에 role이 존재해야한다.
# session name define : ec2-session-${PROFILE} -> session name 임의값으로 지정해주는 것임. 각 프로파일마다 겹치지만 않게 하기 위함.

# 해당 프로파일 세션이 유효한지 체크
# session name 을 구해와서 비교
session_check=$(aws sts get-caller-identity --profile ${PROFILE} --region ${REGION} --query "{User:UserId}" --output text | cut -f2 -d ":" )

# session 비어있으면 같지 않을 것이기에 같지 않으면으로 조건 걸었음.
if [ "$session_check" != "ec2-session-${PROFILE}" ]; then
    echo "Your session is Empty or Expire ($session_check)"
    
    while [ -z $OTPCODE ] || [ "${OTPCODE}" = "" ]; do
        read -p 'Enter your MFA code : ' OTPCODE
        if ! [[ ${#OTPCODE} = 6 && "${OTPCODE//[0-9]/}" == "" ]]; then
            echo "It's invalid code ($OTPCODE)"
            OTPCODE=""
        fi
    done

    # AssumeRole (역할 체인지)
    aws_configure=$(aws sts assume-role \
    --role-arn "arn:aws:iam::${ACCOUNT}:role/ec2-role-${PROFILE}" \
    --role-session-name "ec2-session-${PROFILE}" \
    --serial-number arn:aws:iam::xxxxxxxxxxxx:mfa/${USERNAME} \
    --query "Credentials.{
            AccessKeyId:AccessKeyId,
            SecretAccessKey:SecretAccessKey,
            SessionToken:SessionToken
        }" \
    --tags Key=Role,Value=${ROLE} \
    --transitive-tag-keys Role \
    --token-code ${OTPCODE} \
    --output text )

    if [ -z "${aws_configure}" ]; then
        echo "AssumeRole Fail!!!"
        exit 0
    fi

    aws_access_key_id_value=$(echo "${aws_configure}" | cut -f1)
    aws_secret_access_key_value=$(echo "${aws_configure}" | cut -f2)
    aws_session_token_value=$(echo "${aws_configure}" | cut -f3)

    aws configure set aws_access_key_id "${aws_access_key_id_value}" --profile ${PROFILE}
    aws configure set aws_secret_access_key "${aws_secret_access_key_value}" --profile ${PROFILE}
    aws configure set aws_session_token "${aws_session_token_value}" --profile ${PROFILE}
fi

echo "Select one option using up/down keys and enter to confirm:"

# 키워드(KEYWORD)가 1글자인 경우는 무시..
if [[ ${#KEYWORD} = 1 ]]; then
    KEYWORD=""
fi
# 키워드가 숫자 10으로 시작하는 경우 IP검색으로 조건 변경.
if [[ "$KEYWORD" == 10* ]]; then
    echo "If the keyword starts with 10, the condition is changed to an IP lookup."
    filter_condition="Name=private-ip-address,Values='${KEYWORD}*'"
else
    filter_condition="Name=tag:Name,Values='*${KEYWORD}*'"
fi

if [ "${PROFILE}" = "work-prd-ssm" ]; then
    runmode="Name=tag:RunMode,Values=PRD"
elif [ "${PROFILE}" = "work-dev-ssm" ]; then
    runmode="Name=tag:RunMode,Values=DEV"
fi

IFS=$'\n' options=($(aws ec2 describe-instances \
--profile ${PROFILE} \
--region "${REGION}" \
--query "Reservations[*].Instances[*].{aInstance:InstanceId,bState:State.Name,cIp:PrivateIpAddress,dName:Tags[?Key=='Name']|[0].Value}" \
--filters ${filter_condition} ${runmode} \
--output text))

if [ -z "${options}" ]; then
    echo "No Result !!!"
    exit 0
fi

select_option "${options[@]}"
choice=$?

echo "Choosen index = $choice"
echo "        value = ${options[$choice]}"
instance_id=$(echo ${options[$choice]} | cut -f1 )

echo "instance id: ${instance_id}"

aws ssm start-session  \
--profile ${PROFILE} \
--region ${REGION} \
--target ${instance_id}
