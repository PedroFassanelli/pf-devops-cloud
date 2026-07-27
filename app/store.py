"""Almacenamiento en memoria.

Se usa un store en memoria a propósito: el foco del proyecto es el pipeline,
no la persistencia. Mantener la app stateless permite escalar horizontalmente
con el HPA sin coordinación entre réplicas.
"""

from threading import Lock

from app.metrics import TASKS_TOTAL
from app.models import Task, TaskCreate, TaskStatus, TaskUpdate


class TaskStore:
    def __init__(self) -> None:
        self._tasks: dict[int, Task] = {}
        self._next_id = 1
        self._lock = Lock()
        self._refresh_metrics()

    def _refresh_metrics(self) -> None:
        counts = dict.fromkeys(TaskStatus, 0)
        for task in self._tasks.values():
            counts[task.status] += 1
        for status, total in counts.items():
            TASKS_TOTAL.labels(status=status.value).set(total)

    def list(self, status: TaskStatus | None = None) -> list[Task]:
        tasks = list(self._tasks.values())
        if status is not None:
            tasks = [t for t in tasks if t.status == status]
        return sorted(tasks, key=lambda t: t.id)

    def get(self, task_id: int) -> Task | None:
        return self._tasks.get(task_id)

    def create(self, payload: TaskCreate) -> Task:
        with self._lock:
            task = Task(id=self._next_id, **payload.model_dump())
            self._tasks[task.id] = task
            self._next_id += 1
        self._refresh_metrics()
        return task

    def update(self, task_id: int, payload: TaskUpdate) -> Task | None:
        with self._lock:
            task = self._tasks.get(task_id)
            if task is None:
                return None
            updated = task.model_copy(update=payload.model_dump(exclude_none=True))
            self._tasks[task_id] = updated
        self._refresh_metrics()
        return updated

    def delete(self, task_id: int) -> bool:
        with self._lock:
            removed = self._tasks.pop(task_id, None) is not None
        self._refresh_metrics()
        return removed

    def reset(self) -> None:
        with self._lock:
            self._tasks.clear()
            self._next_id = 1
        self._refresh_metrics()


store = TaskStore()
