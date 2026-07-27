"""Modelos de dominio y esquemas de entrada/salida."""

from datetime import UTC, datetime
from enum import Enum

from pydantic import BaseModel, Field


class TaskStatus(str, Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    DONE = "done"


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    description: str = Field(default="", max_length=1000)
    status: TaskStatus = TaskStatus.PENDING


class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=1000)
    status: TaskStatus | None = None


class Task(TaskCreate):
    id: int
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))


class HealthResponse(BaseModel):
    status: str
    version: str
    environment: str
