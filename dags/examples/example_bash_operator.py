from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator

with DAG(
    dag_id="example_bash_operator",
    start_date=datetime(2025, 1, 1),
    schedule_interval=timedelta(hours=1),
    catchup=False,
    tags=["example", "bash"],
) as dag:
    # Simple task that prints a message
    print_hello = BashOperator(
        task_id="print_hello",
        bash_command="echo 'Hello from Airflow on Kubernetes!'",
    )

    # Task that sleeps briefly (simulates work)
    sleep_task = BashOperator(
        task_id="sleep_task",
        bash_command="sleep 10 && echo 'Slept for 10 seconds'",
    )

    # Task that shows environment info
    show_env = BashOperator(
        task_id="show_env",
        bash_command="echo 'Hostname:' && hostname && echo 'User:' && whoami",
    )

    print_hello >> sleep_task >> show_env