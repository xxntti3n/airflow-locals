from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator

with DAG(
    dag_id="example_task_flow",
    start_date=datetime(2025, 1, 1),
    schedule_interval="@daily",
    catchup=False,
    tags=["example", "dependencies"],
    description="Demonstrates task dependencies and parallel execution",
) as dag:
    # Start node
    start = EmptyOperator(task_id="start")

    # Three parallel tasks
    task_a = BashOperator(
        task_id="task_a",
        bash_command="echo 'Task A executing' && sleep 5",
    )

    task_b = BashOperator(
        task_id="task_b",
        bash_command="echo 'Task B executing' && sleep 8",
    )

    task_c = BashOperator(
        task_id="task_c",
        bash_command="echo 'Task C executing' && sleep 3",
    )

    # Aggregation task
    aggregate = BashOperator(
        task_id="aggregate",
        bash_command="echo 'All parallel tasks completed!'",
    )

    # Final task
    end = EmptyOperator(task_id="end")

    # Define dependencies
    start >> [task_a, task_b, task_c] >> aggregate >> end