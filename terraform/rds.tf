# ---------------------------------------------------------------------------
# RDS POSTGRESQL — ISTNIEJE, DO IMPORTU
#
# HASŁO NIE JEST TU ZARZĄDZANE.
# AWS nigdy nie zwraca master password przez API, więc import go nie wypełni.
# Zamiast wpisywać hasło do konfiguracji (skąd trafiłoby do pliku stanu),
# pomijamy atrybut i jawnie każemy Terraformowi go ignorować. Rotacja hasła
# odbywa się poza Terraformem — w konsoli albo przez AWS CLI.
# ---------------------------------------------------------------------------

resource "aws_db_instance" "postgres" {
  identifier = var.rds_identifier

  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  db_name  = var.rds_database_name
  username = var.rds_username
  # password — celowo nieobecne, patrz blok lifecycle.

  allocated_storage     = 20
  max_allocated_storage = 1000
  storage_type          = "gp2"
  storage_encrypted     = true
  # Klucz zarządzany przez AWS (aws/rds). TODO: po imporcie sprawdź, czy plan
  # nie chce zmienić kms_key_id — jeśli tak, wpisz tu ARN klucza z konsoli.

  publicly_accessible = false
  multi_az            = false
  port                = 5432

  vpc_security_group_ids = [aws_security_group.rds.id]

  db_subnet_group_name = "default-vpc-0de2ad6ec8de9076c"

  backup_retention_period    = 1
  copy_tags_to_snapshot      = true
  deletion_protection        = false
  auto_minor_version_upgrade = true

  performance_insights_enabled = true
  monitoring_interval          = 0

  # ATRYBUTY, KTORYCH AWS NIE ZWRACA
  # Poniższe pola istnieją wyłącznie po stronie Terraforma i po imporcie będą
  # puste. Ustawiamy je zgodnie z intencją, bo nie ma ich z czym porównać.
  skip_final_snapshot = true
  apply_immediately   = false

  lifecycle {
    ignore_changes = [
      # Hasło zarządzamy poza Terraformem.
      password,
      # Auto minor version upgrade potrafi podbić wersję bez naszego udziału.
      engine_version,
      # Nazwa migawki końcowej nie ma odpowiednika po stronie AWS.
      final_snapshot_identifier,
    ]
    # Zabezpieczenie przed przypadkowym zniszczeniem bazy.
    prevent_destroy = true
  }
}
