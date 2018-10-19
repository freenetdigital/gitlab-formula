# vim: sts=2 ts=2 sw=2 et ai
#
{% from "gitlab/map.jinja" import gitlab with context %}

{% if grains['os_family'] == 'Debian' %}
gitlab-runner repo:
  pkgrepo.managed:
    - humanname: gitlab-runner debian repo
    - file: /etc/apt/sources.list.d/gitlab-runner.list
  {%- if gitlab.runner.custom_repo_url != '' %}
    - name: deb {{ gitlab.runner.custom_repo_url }} {{ grains['oscodename'] }} main
  {%- else %}
    - name: deb https://packages.gitlab.com/runner/gitlab-runner/{{ grains['os']|lower }}/ {{ grains['oscodename'] }} main
  {%- endif %}
  {%- if gitlab.runner.custom_repo_gpgkey != '' %}
    - key_url: {{ gitlab.runner.custom_repo_gpgkey }}
  {%- else %}
    - key_url: https://packages.gitlab.com/runner/gitlab-runner/gpgkey
  {%- endif %}

gitlab-install_pkg:
  pkg.installed:
    - name: gitlab-runner
{% else %}
gitlab-install_pkg:
  pkg.installed:
    - sources:
      - gitlab-runner: {{gitlab.runner.downloadpath}}
{% endif %}

gitlab-create_group:
  group.present:
    - name: "gitlab-runner"
    - system: True
    - require:
      - pkg: gitlab-install_pkg

gitlab-install_runserver_create_user:
  user.present:
    - name: {{gitlab.runner.username}}
    - shell: /bin/false
    - home: {{gitlab.runner.home}}
    - groups:
      - gitlab-runner
    - require:
      - group: gitlab-create_group

{%- for runner in gitlab.runner.runners %}
gitlab-install_runner_{{ runner.name }}:
  cmd.run:
    - name: "gitlab-runner register --non-interactive --name {{ runner.name }} --url {{ runner.url }} --registration-token {{ runner.token }} --executor {{ runner.executor }} {% for k, v in runner.env.items() %}--env='{{ k }}={{ v }}' {% endfor %} {{ runner.extra_args }}"
    - require:
      - user: gitlab-install_runserver_create_user
    - unless: gitlab-runner list 2>&1 | grep "\\b{{ runner.name }}\\b"
{%- endfor %}

runner-concurrent-setting:
  file.replace:
    - name: /etc/gitlab-runner/config.toml
    - pattern: "^concurrent = \\d+"
    - repl: "concurrent = {{ gitlab.runner.runners|length }}"
    - count: 1
    - onchanges:
{%- for runner in gitlab.runner.runners %}
      - cmd: gitlab-install_runner_{{ runner.name }}
{%- endfor %}

gitlab-runner:
  service.running:
    - enable: True
    - require:
      - pkg: gitlab-install_pkg
{%- for runner in gitlab.runner.runners %}
      - cmd: gitlab-install_runner_{{ runner.name }}
{%- endfor %}
    - watch:
{%- for runner in gitlab.runner.runners %}
      - cmd: gitlab-install_runner_{{ runner.name }}
{%- endfor %}
      - file: runner-concurrent-setting
