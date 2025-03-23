#!/bin/bash

PRIME_BITS=2048
G=2

read -r -p 'Start as 1) Sender or 2) Listener?: ' MODE

if [[ "$MODE" == "1" ]]; then

  read -r -p 'Destination IP:PORT -> ' DESTINATION
  DESTINATION=$(echo "$DESTINATION" | tr : ' ')
  if ! nc -z $DESTINATION; then
    echo "Error: host doesn't listening" >&/dev/stderr
    exit 1
  fi

  coproc client { netcat $DESTINATION; }
  P=$(openssl prime -generate -bits $PRIME_BITS)
  a=$(openssl rand 128 | od -DAn | tr -d " " | tr -d '\n')
  A=$(qalc -s "exp 0" -b 10 -t "$G"^"$a" % "$P")
  echo "P, a generated. A calculated"
  printf >&${client[1]} "%s\n" "$P $A"
  IFS= read -r -u${client[0]} B
  PASSWORD=$(qalc -s "exp 0" -b 16 -t "$B" ^ "$a" % "$P")
  export PASSWORD="$PASSWORD"
  echo "Password for encryption is saved as \$PASSWORD (if you don't forget to add this script as source)"

  echo "Enter the chat mode? 1) Yes 2) No"
  read -r -p 'Enter your option: ' CHAT_MODE

  if [[ "$CHAT_MODE" == "1" ]]; then
    if ! nc -z $DESTINATION; then
      echo "Error: host doesn't listening" >&/dev/stderr
      exit 1
    fi
    read -r -p 'Enter your username: ' USERNAME

    exec 10<&${client[0]}
    exec 11>&${client[1]}

    while IFS= read -r -u10 message; do
      echo "Recieved encrypted message"
      echo "$message"
      echo "Decrypted:"
      echo $(echo "$message" | openssl enc -d -aes256 -pbkdf2 -a --pass "pass:$PASSWORD")
    done &

    while IFS= read -r input; do

      echo $(echo "$USERNAME: $input" | openssl enc -aes256 -pbkdf2 -a --pass "pass:$PASSWORD") >&11
    done
  fi

  kill $client_PID >&/dev/null
  killall netcat >&/dev/null
elif [[ "$MODE" == "2" ]]; then
  read -r -p 'Port to listening to: ' PORT
  re='^[0-9]+$'
  if ! [[ $PORT =~ $re ]]; then
    echo "error: Not a number" >&2
    exit 1
  fi
  coproc server { netcat -N -lk $PORT; }
  netcat_PID=$(pgrep -f "netcat -N -lk $PORT")

  a=$(openssl rand 128 | od -DAn | tr -d " " | tr -d '\n')

  echo "Waiting for sender..."

  IFS= read -r -u${server[0]} dh_params
  array=($dh_params)
  P=${array[0]}
  B=${array[1]}

  A=$(qalc -s "exp 0" -b 10 -t "$G"^"$a" % "$P")

  printf >&${server[1]} "%s\n" "$A"

  PASSWORD=$(qalc -s "exp 0" -b 16 -t "$B" ^ "$a" % "$P")
  export PASSWORD="$PASSWORD"
  echo "Password for encryption is saved as \$PASSWORD (if you don't forget to add this script as source)"

  echo "Enter the chat mode? 1) Yes 2) No"
  read -r -p 'Enter your option: ' CHAT_MODE

  if [[ "$CHAT_MODE" == "1" ]]; then
    read -r -p 'Enter your username: ' USERNAME

    exec 10<&${server[0]}
    exec 11>&${server[1]}

    while IFS= read -r -u10 message; do
      echo "Recieved encrypted message"
      echo "$message"
      echo "Decrypted:"
      echo $(echo "$message" | openssl enc -d -aes256 -pbkdf2 -a --pass "pass:$PASSWORD")
    done &

    while IFS= read -r input; do
      echo $(echo "$USERNAME: $input" | openssl enc -aes256 -pbkdf2 -a --pass "pass:$PASSWORD") >&11
    done
  fi

  kill $server_PID >&/dev/null
  killall netcat >&/dev/null

fi
