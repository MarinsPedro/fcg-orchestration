FROM rabbitmq:4.3.6-management
COPY plugins/*.ez /opt/rabbitmq/plugins/
RUN rabbitmq-plugins enable --offline rabbitmq_management rabbitmq_prometheus rabbitmq_delayed_message_exchange
