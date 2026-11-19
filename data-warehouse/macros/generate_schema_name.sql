{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name == 'mart' -%}
        mart
    {%- else -%}
        {{ dbt.generate_schema_name(custom_schema_name, node) }}
    {%- endif -%}
{%- endmacro %}
