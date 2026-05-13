import { CommonModule, DatePipe } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';

import { environment } from '../environments/environment';

interface MetricRecord {
  ts: number;
  timestamp: string;
  cpu_percent: number;
  instance_id?: string;
  memory?: {
    used_percent?: number;
    used_mb?: number;
    total_mb?: number;
  };
  disk?: {
    used_percent?: number;
    used_gb?: number;
    total_gb?: number;
  };
  load_average?: {
    '1m'?: number;
  };
  payload?: unknown;
}

interface MetricsResponse {
  thingName: string;
  count: number;
  items: MetricRecord[];
}

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, DatePipe],
  templateUrl: './app.component.html',
  styleUrl: './app.component.css',
})
export class AppComponent implements OnInit {
  private readonly http = inject(HttpClient);

  protected readonly apiBaseUrl = environment.apiBaseUrl;
  protected loading = true;
  protected error = '';
  protected thingName = '';
  protected metrics: MetricRecord[] = [];

  ngOnInit(): void {
    this.loadMetrics();
  }

  protected loadMetrics(): void {
    this.loading = true;
    this.error = '';

    this.http
      .get<MetricsResponse>(`${this.apiBaseUrl}/metrics?limit=20`)
      .subscribe({
        next: (response: MetricsResponse) => {
          this.thingName = response.thingName;
          this.metrics = response.items;
          this.loading = false;
        },
        error: () => {
          this.error = 'Unable to load telemetry from API Gateway. Update environment.prod.ts with the Terraform output URL and make sure Lambda has data.';
          this.loading = false;
        },
      });
  }

  protected trackByTimestamp(_index: number, item: MetricRecord): number {
    return item.ts;
  }
}
