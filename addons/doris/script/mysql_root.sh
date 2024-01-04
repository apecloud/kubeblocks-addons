#!/bin/bash
for i in {1..300}; do
    if [[ $(mysql -uroot -P9030 -h$KB_POD_IP --comments -e "select VERSION()") ]]; then
        fetrueNum=$(mysql -uroot -P9030 -h$KB_POD_IP --comments -e "show frontends\G" | grep Alive | grep true | wc -l)
        feNum=$(mysql -uroot -P9030 -h$KB_POD_IP --comments -e "show frontends\G" |grep Name| wc -l)
        betrueNum=$(mysql -uroot -P9030 -h$KB_POD_IP --comments -e "show backends\G" | grep Alive | grep true | wc -l)
        beNum=$(mysql -uroot -P9030 -h$KB_POD_IP --comments -e "show backends\G" |grep Alive | wc -l)
        echo -e "fetrueNum: $fetrueNum --- feNum: $feNum --- betrueNum: $betrueNum --- beNum: $beNum \n"
        if [ $feNum -eq $fetrueNum ]&&[ $beNum -eq $betrueNum ]; then
            mysql -uroot -P9030 -h$KB_POD_IP --comments -e "SET PASSWORD FOR 'root' = PASSWORD('$MYSQL_ROOT_PASSWORD');"
            printf 'doris fe 启动成功,修改密码!'
            break
        fi
    else
        if [[ $(mysql -uroot -P9030 -h$KB_POD_IP -p$MYSQL_ROOT_PASSWORD --comments -e "select VERSION()") ]]; then
            printf 'doris fe 已经修改完密码!'
            break
        fi
    fi
    sleep 5
done
printf 'doris update root password finished!'
