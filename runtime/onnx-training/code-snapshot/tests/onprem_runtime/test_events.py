from onprem_runtime.core.events import TrainingEvent


def test_training_event_serializes_to_websocket_json():
    event = TrainingEvent(
        job_id="job_123",
        phase="epoch",
        data={"epoch": 2, "epochs": 5, "train_loss": 0.42, "val_acc": 0.81},
    )

    assert event.to_json() == {
        "job_id": "job_123",
        "phase": "epoch",
        "data": {"epoch": 2, "epochs": 5, "train_loss": 0.42, "val_acc": 0.81},
    }
