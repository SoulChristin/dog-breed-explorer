{#- Override dbt's default (target.schema + '_' + custom_schema), so a model's
   custom schema (e.g. `landing`) is used as-is instead of becoming `dev_landing`. #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}