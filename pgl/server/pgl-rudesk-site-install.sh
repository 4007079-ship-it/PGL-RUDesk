#!/usr/bin/env bash
# =====================================================================
#  Сайт PGL-RUDesk на VPS (nginx). Ubuntu / Debian.
#  Запуск:  bash pgl-rudesk-site-install.sh
#  Повторный запуск = обновление страницы.
# =====================================================================
set -euo pipefail
SITE_DIR="/var/www/pgl-rudesk"

green() { echo -e "\e[32m$*\e[0m"; }
[[ $EUID -eq 0 ]] || { echo "Запустите от root"; exit 1; }

green "==> Установка nginx"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null

green "==> Копирование страницы"
install -d "$SITE_DIR"
echo 'H4sICK8j3moCA2luZGV4Lmh0bWwA7VxbjxvHcn7Xr+jQECAlnOH09Fz3hqOsDrwCJMSwYwXxSzAkh+REJIeYmb1IhgFLto8dyDnGUfwQnOAcw8lLgiDAWtZaa+sG+BeQf8G/5FRVzwxnhkMuV5LzJKyWy+nu6q6u+qq6qmvsrb/qhp3k9sRng2Q03LmwhX/Y0Bv3txvRfgMbfK8Lf0Z+4rHOwItiP9lu7Cc9xWlkzWNv5G83DgL/cBJGSYN1wnHij2HYYdBNBttd/yDo+Ao9NFkwDpLAGypxxxv62xwnSYJk6O+88/Z15d33r/rxLfbLx1+z2SfTR9Pj6ZPZH6bPps9m96c/Mmh4Prs7uwddL7ZakqrEQtePO1EwSYJwXODifBOz6U/wb/p8+nT6Yvbl7Peze9OT2cdA8JRNTxk+TZ9Ay6cw4hm1zj6nASfTx2x2F1q/w5mmD6Ehmx6accRD/MT9DoPxLRb5w+1G0EFOB5HfA+a9xNsIRl7fb8UH/b85Gg2bF8UufL2oa/Awji+Kqxd1fZAkk4viSqt1eHioHgo1jPotXdO0Fo3UYTAq4m/DIzlcgwb8tYz8U78ofgszR34ngSZSixyb9urawA/6g6TS2AuGQ9l0URcaTqq3SjOlK3KREtzOOdDL6wjbrVunZpmeZXg9a9lK5XXMxYVyVooLmda5FzI19+yl+GtZqiq9fN7CWoap16wlXlF+3DbWFKB2fgE6+plrmc5rWaoqQN2w1xTgqwJQd9cUoCFeWYB1a9UJ8CWWqgpQWMZ6FvwSyiqvZGj2egIU9iubcP1a/LWsVZWgUWdZjngt2qr4QL6mExTn15Xg4sy1hG6/lrWqEjQdbU0JvioGrWyXZ0lQt19ZgnVr1UrwJdbirlnB++JahmHWrJUBPsq4ts46/ycezLiMO+joytYbujBUS3dczdJhYc00HVXb0y2hukKzIM6A5psmd1VD48KyuWObe7pjqIYQpitsc1dwXXWAQ8tMJyiNhQYhNFUIy+VGtoSmq6ap2Q7Xa/sN21Y1yxaOjiN2F/tNrsqZuVC5aeiuJVcyYCsCEEiMwbPumCrsJOek1L9X3PgHN8o7xsGupeqGjqQ3DRSK6aR0tqtqwtHk467uwv55xi2xNx+MTLiu6pqWZhoZl5apGkZB5IsjygJY7Hcc1QSkWFq+RpWHOfPYDRxznWejC50f3ABVqa49157pqpalcXzcBR2rlsNzkRQ7aaOWauhmpkdTAJtaQRuVbs1SHamKm4arqaZr06J7YASqcIQt5QFY01XNtSyb5tkzdAd41zgnyl1Dt1XbyYSP0+qmahrCNUyRbp2DcOx87ybswdVtWxjp5gF8YIjp9NUBu8AITGe4y8iFDdh17Lm56BqoqoDB6gDDNVXXFakQdxe64VlzCuAWYFuwkVQ4KZxEPhy458KZIzrv3DU4gNvQHDSLGkJdVy2DF5RngQ2bGnikbDgI0rCKc9tGru09wzRBK5KpXYjUVK1kWCZIQbPmlmeAzSIq55YJy5sF3gB1c0srdu4KywHQWaaea6xCKwx4hhPCnm8UROwI4TqZkhZGAOJz0ewudJsCMIRWlZmPsCzV4lxkz1XgL7cZMCgb4Jyjk7ypaYJqAPYmeBwywj10gVa+ws2yY5rP8MHcnVMmKX6LmWqc3MYcm7GNKAwT9iF8Y0xR2v0N9pbW03pc34THiTf2h9DCHe5yH1s6XtSFBvAHXHewAVJeHxs6eleYm+k0iX+UQKPfgZ8ejhrtJz7SuZ7b9gRNDakyNMjTJGtQcEzHFV7HxaYQRwi97XsWzvwR/P41+5C1wyMlDu4EY2C2HUZdP1KgaZP66ZbjQxZ3onA4VNr+wDsIwmiDxSPY5kCOaYfd2zBm5EX9YLzBtE3W9jq3+lG4P4b1D7zoEgri8ibrhEOklS24p8tyg71wDNvj1uSoBRBk8e048UfKftBkijeZDH1FtjRZ4z2/H/rs/WuNJns3bIdJ2GSxN46V2I+CnuTGA1bShYLxANoT2a4eRt6E2DySNyywIqBmAhvNOWfefhJusonX7ZI0NKbTgI8uoCh8D0QDM0zCOMCbE5BCEnRu3d5kSTihfd9RgnHXP9pgZlkGUb/tXeJmE/85TdVx0o3jmG4UThSICBIfOG4P96NLzuQIhJVrIknCEfA6OWJxOAy6qfgQJ5dTHUnGsg12g3gy9G5vsN7QB969YdAfKwHIL95gHX8M62yyvgcMcx33JkOaDWalOwVJtSNv3D3XTESLGlW6fieMPCmecTgGkKN2lcN0FVvT0hZAHACdO5VVwaRg5VRBosShfErlEnndYB/4sDP6sXeQg1AZ+j0gkNqs7IIY1mmqIh9GcR7E0JLdlDBMZni5QLcxCA8II6VhaIqXUxSpcRIFEz8u4chrg2phrk2AbOwnZSzB93DidYIEtgAHDcAzDFD2in8AOohTxnI85ZjzJz5wPu4TVLxI6aPIgOISd7Su328WmUOkg0iaLAElxBMvgnHUwkwd0Uizj7z4lkL3bhusOqcrpyyQN8HxaRqDjCD9ZuO3woBUbirYaFiSRuQPgfEDkAYKszcMDzfYIOh2/XHBNB1QGHBtWwVMrGErcrXMVOrWzOXOC9DpR0F3kz7Bb42gLfEVUPH+aAzy56reA/Nzepk5SK9Say5zHgYcGCggsDP0RpNLwkItWAeHTTJI4BqZVzIT4BDFFv2VlhrQ0E8QETHiBKWjqGZuV9lq0Dleisxs3KQ6IoP4gs0WmRCpG809q6nPvckw7IdKOyiYNYecqDRcyOH/vA8OtXcbvPmwNxdZxeB1XJ3wGO4n8rRcou+0Xwl7PTIqXsOTdDe5ntvDsHNrs8xnJnvpTeq4SS27nYyLcwVjWv0s3+kUXZxBcC6eP3U+jzaSn5y5b7XQt65ywqn6CBpkiCn4524DHIwZNyUC6Hvmm5OxMvIC3N/i2Z6CKIXNW71er0KVe8V6WiVzoUTQH4RxQlEJ7nlRueXVSm0l51/Qdj5tLSN0OEPi1rSNJv5ReearY7+DAkJHkWnERp+onet01st2LrSq9cyPwCGc5MsMsGRvxhx16JSKsFvpquShcMloslEwBgO8pDUZ70WXL2cHeX4Mqt1hrcIwYM2jk6UbrwLWKMGaDhae2/ESyFbObfxUukEkdbLB5J5Svq0FSEsG5kBOj55eGI2KwO4O55gokFSAlZNuyK8o1H+8pNDRmEurHLkYpciFnvDapx6xGYycovTbZdxwu9gZj7zhcB1fLXKqcZj4a1OkjFFgyws+DuLwSXxeuInVcOsAvvD0inxy05lqcKl6n4FZ1NkgwwBBnivpQOkXjHp/ki+5sdH2QdVSVJKxYNyJ/JE/lsyl5dKNrPtSfHlzwetLsUBTx694fYJ8hhKthBKtxteT7IsywFiq3v0tBtoVeMmAfy7cgSimbfBjVaNiu0wwKad5Z0Kp4KZ6AITXhhsdGE3F9VE+eTc4mHvq7BCwFvSvrwgOaZ4FqRhVqVjlhV9BKpC3SudT5+wwSN1g+Fkyl9pQYqmVyLzgVbw1mn8ah0jvg/cb8xCpiGBeh2ATg6hF/sJbtPKREg+8Lob4WiZseSKbWpO78GvhieykGuqEXT9ziz1vFAxBYvuBMgrHIca+fpPthmPYoQf+Pm9c035IUvmuwQumtlfejbUkcbyAwRh42KgYLQiZpBipm1vXVacTLUnol2BDy00iC6NzR0VSUNp+cuhjDlVYwluSECw5kmmbvxn53cBjlwrxu4N+9nJ661VOsZblTL00GSonCIU5dY02kyJX4fnwNOBZ7Tr0GteR0tMR1sw90tkMypuFXAuZKGiyYsSa+QBOMSK6go/olm2rld4ObrXSd4TwxmzngnxlyI/w2nALvRekgHG83UDJNXZo/i0va6TbkewNmLcaO1sYbtDbLtsNfNNlo/Y9lwZL33HZbpB/N+gXqDGMkja83cCW1ITTB4xUYBWYpNFKx8IMXEDXbZipkVEK2y1S5oTyFrJIKynNOSlNlpGa1gpSU3MXifmaxBnPRJFSG6ZeoBZncs1tYwnb2iq2HX2B2nTWJM7Y1g17CdtnC1t3l7BtiDXYLlIX2V5JnLEtLKMeIys3LWkNza5nW9hrgKRMzdekzvg2ipp2xJq7TrHNl4BbrNqz4GKBWuj2mtQZ36ajLeH7bHlbyEEd37q9Bt9F6hLfK6m5a6bamlMbhlmgRnVFuI5V9UZYQ6/MzLrbjVLNnL1axZyVR7JytZsVa+XVvpV1ciar5KxUI2elQhMr1cfZ+tVx9nK1cVYcyspVbVauii/0rqqIs3I9nFVXnTPLipVwtrQOzpZXwUtdrFjiZqX6d6XrV6h9s3LlmxXr3qxUtmblmjdbUfGuEJaq1axc6650rqpzs3KVm5Vr3GxeqGal+jZbWt0ukZQq26xc12blqjZbt6bNyhVtVqpns1JFms1r2WxVJbtCVS5Cs3INe6F3Rf2alavXrFS7rsB1GcaLVWv2qjVrdJwYD0LYCHlh4Q1yaMWGrZaXBpwQ7MpvFHym4SbkZ+Nh6HUbO9Nvpz9Nj2efw++92Zc5WXHwIDyEcX+cHuP74S+mz6ePgOTJ7PdAdIpEs7uzr2oJMSDfj/wYqB8A2ePpU/j8YfpMvnI+PZ0z2Uq53GpB2JzF1RhIXyjG0ZiHNKrBdVp+gxBY0i4PvdNu+j7gO9P/Wv02vJTs9Dt6vx33DT34svsjGH5K78k/zIUN02UzT4qv81fEdTw9md37lV+zV9n0/6Y/0YTPmmz6dHZ/9sXsyyYu+QTaHgLvqOpPcAQt+Cm0/ggM3pf/jcBdNvsC9Pop9MMOcRagOJHMpcKYfQ4C+gEGfcaQHZqX5KFutSYFGGSZTjJmWeWgcT4EVmagxKzxUrjM0VHGR5aqvsm/3uRfb/KvN/nXm/zrTf71Jv96k3+9yb/e5F/r5V951pGlLvTnwlb2rkkAvnQe7K5ITwZ6JRRmxawOeuWwSR66+mn0nIf+jMLyEwZPLyAEvovBOzxAcEzB/Pcyy4CU4BMK9WVOg8kGEFJOgcE+Bv0/YawPcT9mHtPvp8/x4ZgSI5zhFNMCYhCaYbVntCxQzsP/4h6xHtNYjOm7QzhmvMRTQnj4h2AMMoqz0B7j7xgC8H6QDPbbaicctQwNoGC7SjwIJkqQtOayaUU+iCL241Ym5takP1Si/S52zscpR471T2A4/pGfswMMYdhfiul1A/410nMRD0LBAHuMa8xQzQN7T9y5wTl8h2GciQNwSHuc34FR4NfMgX1gX4ev0ErDqI1rN3U+VLimcNW4k0NnzkN7JxXAVqsNiQi+CgLpaVEls3/BnJMh8+znx5BzKJB3QZYDM9HoTLx12VNJ0lfG3SgMur+upPfHwYEfxd5Q9Sa3zidsi7kDrh84HshOvg+pwLeBwg/EQNEPFPg0DsSeA9/27OIgBXRgIDGoyLgz4ibT8PsA223Qn8EsVTBdNYaqpYDyODxB8HDFYpacAnTFhDd/FKqj2te5rXKmA41qXOcWznMFvEdG4TBnz/IKDaqpGHduuDAOMOPBDA61Uy/MIZ/pB7Bg3RkB4dmjahGTKrKImG/APE/BnvGS5UTm7Qw1cG6QXA/G+0f/L8bY9dvnwwcoSe8ocNSDbASaperSX/DTJD2dlMxV1J+ukI4tGG7AowEDOejFTtUvR4LcgYZa8NdmAofCL8QIsApqFE1d5fAnxvktmt/ocJwIBoOK3HR2gU1IYyBoYVmhQAv+gWBNgXgAOVCIAx3I4EfRGbXquxydDKzJIAiAPSIa9TsjGAV7m0OEVyDCMyCJIpCWjULpwXE95NDjQouDhgOc8XqIEQxKAKOLHrzDQsWhI3q/vT9O9lmLXfXbgTc+N9JGXufv3vt1keZ5UWeAUBv1zwk1CxEBCu9ooD+Iq0FPNiFBoMxIhbZC+ocWQJlCYIFhjFpAxjE00ncAgrsLvgX0C6cIswky4OtUs0N6QFxQuy0dkwZAcxHOCHCGoBOICgK8BLqjEBlM7MQAIvquOh1EsYaIRgZpWiJSJLoNBGL61yX/otNWeApQHSBigInoHcQojtQBoQRQhdNoHbcsrcKCrymHCpobuj80PIK9RYax5LQjrReB9efpdxRaPGaoJgTWFfzvhNgN/svH/3bDWAar4qVeHhfha5EQF309+xjiku/JCVLAgr4RTlMIXORNJzFBkQ27Nk78YZOpoziAz2gyarIr796QQRL251faL4nQxOsXwNlg9PrIdkO+qFN4T6exkwdZGH39jliny93P8ntaee/s7RSCrcrWaWMbMuo7xShPBojP8Q73MUzyAqM9tGMG8d89uit+Pv0RL54ZRJOnFHacQJyId8snxdAPRlFo+MvvHrDpH/F+Gpg6nT7CwwaYPaXb9C+z+32MD7MrYxj7Aqcp9OEkP//v9AE8/oHRlh9ib87T7D4O+/lJts88vk4D62qMTbfBZ4TXZ90VLw2y/5NEOfsC6L8HPBAwTlE39xndqD/CWTCO/tfs6p1NH6UAfE4RtIywU1HL+/vj+niZXmeaB8yVHnBQA1EJDtPFCap0IX9cuxzsT4B725n+uxwKrc+beOGPl/f4ILME1EFN2QJ+71Id4bRIndYycmrILWhXBctcvgfABVY4JPSuXWUSrcc00RMsBaT8/hmtQTL1EzoJMuP7lNlA8kLQ/pFR1kRlJUbjSBjE6CdkCYivJ7OvCNloCjUSOlmb9QdUfsm0nrNegZUUWb6NB5SVfVEgeiiJKAO7m3N53CTGIYh7mo4FO/mmHrM/P5FALPFTFGJ1S4v56hJ7mhfvzjCqJaW9pbZEFt/EItI9yiyz7BGrb6Ag6Qu+Q0yhjkmDH5Nq7xLKvqLA9rTedpDpkulIdX1DQkZbOSnBIYuScxWdq3IGZ9Yn4AAx8Sare0rTHdeDKGPkJK0hUpZfceoZTuR0iIncrgDv0lRlKv+INpRH+ejZ58k8lQjBf+YuZgkz/71Y5st5wIuIh6TYVGo1NUFG1vgDMUMuDouThEK8F6AT7KtV63+bWW6hepkz8DWtkh9BJ+nOZ5/h7mdfQQhaKovOBZXylk+K59n9VWz8R+pW5NF1jAhE2nsFy4XECnD3lCRRMfMsz8Jmdu2dvERa2NNqLTzAoUj+hND1Ke0DsJctnt4MNGW80mQUlCP80gTwZQz8jCp57vDoZfaGfMcgD9/DBGvtsvDdLt8/FS+s2vlWibom5JGvTDd2rl1ViuLayCbHd8N3uGmrOl4ROxAbb7Wobb2JN+evYuM73Q08cH6oBjQn9TdkcBQw8hpk0wi32ZcQUf2pPhT6VsKFHq5dbb3rD73b5Zp8uqWzFSRf416lH5ro5/9h7924iXFyHpqOvGCYhBtpOPqbPj5jgNrYWWjC8LFEe66wtrHzdpDs7bdxltK+5PsSf6IgRIZ6uHv27n6c0MsQwPQ7+1E89MY++3u/M2DvJL7KriddFZkBO6SIF+geo+dgV95+5zokHtp8jVxgmZTgq3zzGoyF/ieOfwFT21TW1VEAAA==' | base64 -d | gunzip > "$SITE_DIR/index.html"

if grep -q 'PGL-RUDesk HTTPS' /etc/nginx/sites-available/pgl-rudesk 2>/dev/null; then
  green "==> HTTPS уже настроен, конфигурацию nginx не трогаю"
else
cat > /etc/nginx/sites-available/pgl-rudesk <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/pgl-rudesk;
    index index.html;
    server_tokens off;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    location / { try_files $uri $uri/ =404; }
}
NGINX
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/pgl-rudesk /etc/nginx/sites-enabled/pgl-rudesk
fi
nginx -t -q
systemctl enable --now nginx >/dev/null
systemctl reload nginx

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 80/tcp >/dev/null
fi

IP="$(curl -4 -fs --max-time 5 https://ifconfig.me || hostname -I | awk '{print $1}')"
echo
green "================================================================"
green "  Сайт PGL-RUDesk опубликован:  http://$IP"
green "================================================================"
echo "  Если страница не открывается — откройте порт 80 (TCP)"
echo "  в файрволе панели хостера."
