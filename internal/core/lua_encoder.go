package core

import (
	"fmt"
	"reflect"
	"sort"
	"strconv"
	"strings"
)

func EncodeLuaLiteral(value any) (string, error) {
	var builder strings.Builder
	if err := encodeLuaValue(&builder, reflect.ValueOf(value)); err != nil {
		return "", err
	}
	return builder.String(), nil
}

func encodeLuaValue(builder *strings.Builder, value reflect.Value) error {
	if !value.IsValid() {
		builder.WriteString("nil")
		return nil
	}

	for value.Kind() == reflect.Interface || value.Kind() == reflect.Pointer {
		if value.IsNil() {
			builder.WriteString("nil")
			return nil
		}
		value = value.Elem()
	}

	switch value.Kind() {
	case reflect.Bool:
		if value.Bool() {
			builder.WriteString("true")
		} else {
			builder.WriteString("false")
		}
		return nil
	case reflect.String:
		builder.WriteString(strconv.Quote(value.String()))
		return nil
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		builder.WriteString(strconv.FormatInt(value.Int(), 10))
		return nil
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uintptr:
		builder.WriteString(strconv.FormatUint(value.Uint(), 10))
		return nil
	case reflect.Float32, reflect.Float64:
		builder.WriteString(strconv.FormatFloat(value.Float(), 'f', -1, 64))
		return nil
	case reflect.Slice, reflect.Array:
		return encodeLuaArray(builder, value)
	case reflect.Map:
		return encodeLuaMap(builder, value)
	case reflect.Struct:
		return encodeLuaStruct(builder, value)
	default:
		return fmt.Errorf("unsupported lua encoding kind: %s", value.Kind())
	}
}

func encodeLuaArray(builder *strings.Builder, value reflect.Value) error {
	builder.WriteByte('{')
	for index := 0; index < value.Len(); index++ {
		if index > 0 {
			builder.WriteByte(',')
		}
		if err := encodeLuaValue(builder, value.Index(index)); err != nil {
			return err
		}
	}
	builder.WriteByte('}')
	return nil
}

func encodeLuaMap(builder *strings.Builder, value reflect.Value) error {
	if value.Type().Key().Kind() != reflect.String {
		return fmt.Errorf("unsupported lua map key type: %s", value.Type().Key().Kind())
	}
	keys := value.MapKeys()
	sort.Slice(keys, func(i, j int) bool {
		return keys[i].String() < keys[j].String()
	})
	builder.WriteByte('{')
	for index, key := range keys {
		if index > 0 {
			builder.WriteByte(',')
		}
		builder.WriteByte('[')
		builder.WriteString(strconv.Quote(key.String()))
		builder.WriteString("]=")
		if err := encodeLuaValue(builder, value.MapIndex(key)); err != nil {
			return err
		}
	}
	builder.WriteByte('}')
	return nil
}

func encodeLuaStruct(builder *strings.Builder, value reflect.Value) error {
	type fieldEntry struct {
		name  string
		value reflect.Value
	}
	entries := []fieldEntry{}
	valueType := value.Type()
	for index := 0; index < value.NumField(); index++ {
		field := valueType.Field(index)
		if field.PkgPath != "" {
			continue
		}
		name, omitEmpty := parseJSONTag(field.Tag.Get("json"), field.Name)
		if name == "-" {
			continue
		}
		fieldValue := value.Field(index)
		if omitEmpty && isEmptyValue(fieldValue) {
			continue
		}
		entries = append(entries, fieldEntry{name: name, value: fieldValue})
	}
	builder.WriteByte('{')
	for index, entry := range entries {
		if index > 0 {
			builder.WriteByte(',')
		}
		builder.WriteByte('[')
		builder.WriteString(strconv.Quote(entry.name))
		builder.WriteString("]=")
		if err := encodeLuaValue(builder, entry.value); err != nil {
			return err
		}
	}
	builder.WriteByte('}')
	return nil
}

func parseJSONTag(tag string, fallback string) (string, bool) {
	if tag == "" {
		return fallback, false
	}
	parts := strings.Split(tag, ",")
	name := parts[0]
	if name == "" {
		name = fallback
	}
	omitEmpty := false
	for _, part := range parts[1:] {
		if part == "omitempty" {
			omitEmpty = true
		}
	}
	return name, omitEmpty
}

func isEmptyValue(value reflect.Value) bool {
	switch value.Kind() {
	case reflect.Array, reflect.Map, reflect.Slice, reflect.String:
		return value.Len() == 0
	case reflect.Bool:
		return !value.Bool()
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return value.Int() == 0
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uintptr:
		return value.Uint() == 0
	case reflect.Float32, reflect.Float64:
		return value.Float() == 0
	case reflect.Interface, reflect.Pointer:
		return value.IsNil()
	default:
		return false
	}
}
