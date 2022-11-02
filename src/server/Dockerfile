FROM node:16-alpine
WORKDIR /app
COPY . .
RUN npm install
EXPOSE 8090/tcp
EXPOSE 1900/udp
ENV MYQ_SERVER_PORT="8090"
CMD ["node", "server.js"]