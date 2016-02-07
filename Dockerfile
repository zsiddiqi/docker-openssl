FROM jordi/openssl
MAINTAINER Jordi Íñigo Griera

RUN apt-get update
RUN openssl dhparam -out /etc/ssl/certs/dhparam.pem 4096
RUN apt-get install -y nginx gettext-base \
    && rm -rf /var/lib/apt/lists/*
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log
COPY openssl-nginx/nginx.conf /etc/nginx/sites-available/default

ENV PASSWORD contrasenya

# CA
WORKDIR /root
RUN mkdir -p ca/private ca/db crl certs reqs
RUN chmod 700 ca/private
RUN cp /dev/null ca/db/ca.db
RUN cp /dev/null ca/db/ca.db.attr
RUN echo 01 > ca/db/ca.crt.srl
RUN echo 01 > ca/db/ca.crl.srl
ADD openssl-ca/ca.conf etc/ca.conf
RUN openssl req -passout env:PASSWORD -new -config etc/ca.conf -out ca/ca.csr -keyout ca/private/ca.key
RUN openssl ca -batch -passin env:PASSWORD -selfsign -config etc/ca.conf -in ca/ca.csr -out ca/ca.crt -extensions ca_ext
RUN #-----CA-certificate----------------------------------------------
RUN cat ca/ca.crt
RUN #-----EMPTY-CRL---------------------------------------------------
RUN openssl ca -batch -passin env:PASSWORD -config etc/ca.conf -gencrl -keyfile ca/private/ca.key -cert ca/ca.crt -out /root/ca/crl.pem
RUN cat /root/ca/crl.pem
RUN openssl crl -inform PEM -in /root/ca/crl.pem -outform DER -out /root/ca/crl.crl
# RUN rm /root/ca/crl.pem

# nginx server End-Entity
RUN mkdir -p  server/private
RUN chmod 700 server/private
ADD openssl-nginx/server.conf etc/server.conf
ADD openssl-nginx/bash_history .bash_history
RUN openssl req -passout env:PASSWORD -new -config etc/server.conf -out reqs/server.csr -keyout server/private/server.key
RUN #-----SERVER-Certificate------------------------------------------
RUN cat reqs/server.csr
RUN #-----SERVER-PrivateKey-(CLEAR-TEXT)------------------------------
RUN cat server/private/server.key
RUN openssl req -in reqs/server.csr -noout -text
# RUN openssl s_server -key server/private/server.key -cert server/server.crt -accept 443 -www

# certify nginx
RUN openssl ca -batch -passin env:PASSWORD -config etc/ca.conf -in reqs/server.csr -out certs/server.crt -extensions server_ext

# client End-Entity
RUN mkdir -p  ee/private
RUN chmod 700 ee/private
ADD openssl-client/browser.conf etc/browser.conf

RUN openssl req -passout env:PASSWORD -new -config etc/browser.conf -out reqs/browser.csr -keyout ee/private/browser.key
RUN openssl req -in reqs/browser.csr -noout -text

RUN #-----CLIENT-Certificate------------------------------------------
RUN openssl ca -batch -passin env:PASSWORD -config etc/ca.conf -in reqs/browser.csr -out certs/browser.crt -extensions user_ext
RUN openssl pkcs12 -passout env:PASSWORD -passin env:PASSWORD -export -in certs/browser.crt -inkey ee/private/browser.key -out ee/private/browser.p12 -name "User Certificate"
RUN #-----CLIENT-PrivateKey-(PKCS #12:contrasenya)--------------------
# RUN cat ee/private/browser.p12
RUN cat ee/private/browser.key

# nginx
EXPOSE 443
CMD ["nginx", "-g", "daemon off;"]
